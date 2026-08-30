#
# Author:: Chef Partner Engineering (<partnereng@chef.io>)
# Copyright:: Copyright (c) 2015 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "timeout" unless defined?(Timeout)

require "kitchen"
require "vcoworkflows"
require_relative "version"

module Kitchen
  # Test Kitchen's driver plugins.
  module Driver
    # Test Kitchen driver for VMware vRealize Orchestrator (vRO).
    #
    # This driver does not build a machine itself. It runs two vRO workflows
    # you supply -- one to create a server and one to destroy it -- and treats
    # their output parameters as the machine's identity.
    #
    # The create workflow must return two output parameters, +server_id+ and
    # +ip_address+, both non-empty. +server_id+ is stored in instance state
    # and handed back to the destroy workflow, and +ip_address+ becomes the
    # address the transport connects to. A workflow that completes without
    # those two fails the +create+, since there would be nothing to connect to
    # and nothing to tear down later.
    #
    # @see https://www.vmware.com/products/vrealize-orchestrator.html vRealize Orchestrator
    class Vro < Kitchen::Driver::Base
      # Reader and writer are declared separately rather than as one
      # attr_accessor so that each direction can carry its own tags: YARD
      # shares a single docstring between the two halves of an accessor, and
      # a @param on that shared docstring is a tag the reader cannot have.

      # @return [String] name of the workflow currently being run
      attr_reader :workflow_name

      # Prefer {#set_workflow_vars}, which also clears the memoized client and
      # output parameters. Setting this on its own leaves both pointing at the
      # previous workflow.
      #
      # @param value [String] name of the workflow to run next
      # @return [String] the name just set
      attr_writer :workflow_name

      # @return [String, nil] id of the workflow currently being run, used
      #   to disambiguate when several workflows share a name
      attr_reader :workflow_id

      # Prefer {#set_workflow_vars}, for the same reason as {#workflow_name=}.
      #
      # @param value [String, nil] id of the workflow to run next, or nil when
      #   the name alone identifies it
      # @return [String, nil] the id just set
      attr_writer :workflow_id

      kitchen_driver_api_version 2
      plugin_version Kitchen::Driver::VRO_VERSION

      required_config :vro_username
      required_config :vro_password
      required_config :vro_base_url
      required_config :create_workflow_name
      required_config :destroy_workflow_name

      default_config :vro_disable_ssl_verify, false
      default_config :create_workflow_id, nil
      default_config :destroy_workflow_id, nil
      default_config :create_workflow_parameters, {}
      default_config :destroy_workflow_parameters, {}
      default_config :request_timeout, 300

      # @return [String] the driver's display name in `kitchen list`
      def name
        "vRO"
      end

      # Runs the create workflow and waits for the server to be reachable.
      #
      # Returns immediately if state already names a server, so a re-run does
      # not create a second one.
      #
      # @param state [Hash] mutable instance state; gains +server_id+ and
      #   +hostname+
      # @return [void]
      def create(state)
        return unless state[:server_id].nil?

        info("Executing the create-server workflow...")
        execute_create_workflow(state)

        info("Server #{state[:hostname]} (#{state[:server_id]}) created.  Waiting for it to be ready...")
        wait_for_server(state)
        info("Server #{state[:hostname]} (#{state[:server_id]}) ready.")
      end

      # Runs the destroy workflow for the server named in state.
      #
      # Clears +server_id+ and +hostname+ afterwards. Test Kitchen persists
      # the state hash even when an action fails, so leaving a destroyed
      # server named in it means the next +kitchen destroy+ runs the destroy
      # workflow again against a machine that is already gone.
      #
      # @param state [Hash] mutable instance state naming the server; loses
      #   +server_id+ and +hostname+
      # @return [void]
      def destroy(state)
        return if state[:server_id].nil?

        server_id = state[:server_id]
        hostname  = state[:hostname]

        info("Executing the destroy-server workflow for #{hostname} (#{server_id})...")
        execute_destroy_workflow(state)

        state.delete(:server_id)
        state.delete(:hostname)

        info("Server #{hostname} (#{server_id}) destroyed.")
      end

      # Connection settings for the vRO API.
      #
      # @return [VcoWorkflows::Config]
      def vro_config
        @vro_config ||= VcoWorkflows::Config.new(
          url: config[:vro_base_url],
          username: config[:vro_username],
          password: config[:vro_password],
          verify_ssl: verify_ssl?
        )
      end

      # Client for the workflow named by {#workflow_name} and {#workflow_id}.
      #
      # Memoized, and reset by {#set_workflow_vars}, so switching from the
      # create workflow to the destroy workflow builds a fresh client rather
      # than reusing the previous workflow's.
      #
      # @return [VcoWorkflows::Workflow]
      def vro_client
        @vro_client ||= VcoWorkflows::Workflow.new(
          workflow_name,
          id: workflow_id,
          config: vro_config
        )
      end

      # @return [Boolean] whether to verify the vRO server's TLS certificate
      def verify_ssl?
        !config[:vro_disable_ssl_verify]
      end

      # Points the driver at a different workflow.
      #
      # Clears the memoized client and the memoized output parameters, which
      # is what makes it safe to run the destroy workflow after the create
      # workflow in the same process. Without the second reset, anything
      # reading {#output_parameters} after the switch would still be looking
      # at the previous workflow's output.
      #
      # @param name [String] workflow name
      # @param id [String, nil] workflow id, when the name is ambiguous
      # @return [void]
      def set_workflow_vars(name, id)
        @vro_client        = nil
        @output_parameters = nil
        @workflow_name     = name
        @workflow_id       = id
      end

      # Runs the create workflow and records what it produced.
      #
      # @param state [Hash] mutable instance state; gains +server_id+ and
      #   +hostname+
      # @return [void]
      # @raise [RuntimeError] if the workflow did not complete successfully,
      #   or did not return a usable +server_id+ and +ip_address+
      def execute_create_workflow(state)
        set_workflow_vars(config[:create_workflow_name], config[:create_workflow_id])
        set_workflow_parameters(config[:create_workflow_parameters])
        execute_workflow
        wait_for_workflow

        raise "The workflow did not complete successfully. Check the vRO UI for more info." unless workflow_successful?

        validate_create_output_parameters!

        state[:server_id] = output_parameter_value("server_id")
        state[:hostname]  = output_parameter_value("ip_address")
      end

      # Runs the destroy workflow, passing it the stored +server_id+.
      #
      # @param state [Hash] instance state naming the server
      # @return [void]
      # @raise [RuntimeError] if the workflow did not complete successfully
      def execute_destroy_workflow(state)
        set_workflow_vars(config[:destroy_workflow_name], config[:destroy_workflow_id])
        set_workflow_parameters(config[:destroy_workflow_parameters])
        vro_client.parameter("server_id", state[:server_id])
        execute_workflow
        wait_for_workflow

        raise "The workflow did not complete successfully. Check the vRO UI for more info." unless workflow_successful?
      end

      # Submits the current workflow for execution.
      #
      # @return [void]
      # @raise [RestClient::BadRequest] if vRO rejects the request, after
      #   logging the response body, which is where vRO puts the reason
      def execute_workflow
        vro_client.execute
      rescue RestClient::BadRequest => e
        error("The workflow execution request failed: #{e.response}")
        raise
      rescue => e
        error("The workflow execution request failed: #{e.message}")
        raise
      end

      # Polls until the running workflow's token is no longer alive.
      #
      # @return [void]
      # @raise [Timeout::Error] if it does not finish within +request_timeout+
      def wait_for_workflow
        wait_time = config[:request_timeout]
        Timeout.timeout(wait_time) do
          loop do
            token = vro_client.token
            break unless token.alive?

            sleep 2
          end
        end
      rescue Timeout::Error
        raise Timeout::Error, "Workflow did not complete in #{wait_time} seconds. Please check the vRO UI for more information."
      end

      # Waits for the transport to accept a connection.
      #
      # A server that never becomes reachable is destroyed before the error is
      # re-raised, so a failed create does not leave a machine behind.
      #
      # @param state [Hash] instance state describing how to connect
      # @return [void]
      def wait_for_server(state)
        instance.transport.connection(state).wait_until_ready
      rescue => e
        error("Server #{state[:hostname]} (#{state[:server_id]}) not reachable. Destroying server...")

        begin
          destroy(state)
        rescue => destroy_error
          # Report the leaked machine, but keep the connection failure as the
          # error that surfaces -- it is the one that explains the run.
          error("The destroy-server workflow also failed: #{destroy_error.message}. " \
                "The server may still exist; check the vRO UI.")
        end

        raise e
      end

      # Sets input parameters on the current workflow.
      #
      # @param data [Hash] parameter names to values; names are stringified
      # @return [void]
      def set_workflow_parameters(data) # rubocop:disable Naming/AccessorMethodName
        data.each do |key, value|
          vro_client.parameter(key.to_s, value)
        end
      end

      # Output parameters from the finished workflow run.
      #
      # @return [Hash{String => VcoWorkflows::WorkflowParameter}]
      def output_parameters
        @output_parameters ||= vro_client.token.output_parameters
      end

      # @param key [String] output parameter name
      # @return [String] the parameter's value, stringified; an empty string
      #   when the workflow did not return that parameter at all
      def output_parameter_value(key)
        parameter = output_parameters[key]
        return "" if parameter.nil?

        parameter.value.to_s
      end

      # @param key [String] output parameter name
      # @return [Boolean] true when the parameter is missing or empty
      def output_parameter_empty?(key)
        output_parameter_value(key).empty?
      end

      # Checks that the create workflow returned what the driver needs.
      #
      # @return [void]
      # @raise [RuntimeError] if +server_id+ or +ip_address+ is absent or empty
      def validate_create_output_parameters!
        raise "The workflow output did not contain a server_id and ip_address parameter." unless
          output_parameters.key?("server_id") && output_parameters.key?("ip_address")

        raise "The server_id parameter was empty." if output_parameter_empty?("server_id")
        raise "The ip_address parameter was empty." if output_parameter_empty?("ip_address")
      end

      # @return [Boolean] whether the workflow run reached the "completed" state
      def workflow_successful?
        vro_client.token.state == "completed"
      end
    end
  end
end
