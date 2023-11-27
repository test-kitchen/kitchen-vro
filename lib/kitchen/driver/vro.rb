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

require "kitchen"
require "vcoworkflows"
require_relative "vro_version"

module Kitchen
  module Driver
    class Vro < Kitchen::Driver::Base
      attr_accessor :workflow_name, :workflow_id

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

      def name
        "vRO"
      end

      def create(state)
        return unless state[:server_id].nil?

        info("Executing the create-server workflow...")
        execute_create_workflow(state)

        info("Server #{state[:hostname]} (#{state[:server_id]}) created.  Waiting for it to be ready...")
        wait_for_server(state)
        info("Server #{state[:hostname]} (#{state[:server_id]}) ready.")
      end

      def destroy(state)
        return if state[:server_id].nil?

        info("Executing the destroy-server workflow for #{state[:hostname]} (#{state[:server_id]})...")
        execute_destroy_workflow(state)
        info("Server #{state[:hostname]} (#{state[:server_id]}) destroyed.")
      end

      def vro_config
        @vro_config ||= VcoWorkflows::Config.new(
          url: config[:vro_base_url],
          username: config[:vro_username],
          password: config[:vro_password],
          verify_ssl: verify_ssl?
        )
      end

      def vro_client
        @vro_client ||= VcoWorkflows::Workflow.new(
          workflow_name,
          id: workflow_id,
          config: vro_config
        )
      end

      def verify_ssl?
        !config[:vro_disable_ssl_verify]
      end

      def set_workflow_vars(name, id)
        @vro_client    = nil
        @workflow_name = name
        @workflow_id   = id
      end

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

      def execute_destroy_workflow(state)
        set_workflow_vars(config[:destroy_workflow_name], config[:destroy_workflow_id])
        set_workflow_parameters(config[:destroy_workflow_parameters])
        vro_client.parameter("server_id", state[:server_id])
        execute_workflow
        wait_for_workflow

        raise "The workflow did not complete successfully. Check the vRO UI for more info." unless workflow_successful?
      end

      def execute_workflow
        vro_client.execute
      rescue RestClient::BadRequest => e
        error("The workflow execution request failed: #{e.response}")
        raise
      rescue => e
        error("The workflow execution request failed: #{e.message}")
        raise
      end

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

      def wait_for_server(state)
        instance.transport.connection(state).wait_until_ready
      rescue
        error("Server #{state[:hostname]} (#{state[:server_id]}) not reachable. Destroying server...")
        destroy(state)
        raise
      end

      def set_workflow_parameters(data) # rubocop:disable Style/AccessorMethodName
        data.each do |key, value|
          vro_client.parameter(key.to_s, value)
        end
      end

      def output_parameters
        @output_parameters ||= vro_client.token.output_parameters
      end

      def output_parameter_value(key)
        output_parameters[key].value.to_s
      end

      def output_parameter_empty?(key)
        output_parameter_value(key).nil? || output_parameter_value(key).empty?
      end

      def validate_create_output_parameters!
        raise "The workflow output did not contain a server_id and ip_address parameter." unless
          output_parameters.key?("server_id") && output_parameters.key?("ip_address")

        raise "The server_id parameter was empty." if output_parameter_empty?("server_id")
        raise "The ip_address parameter was empty." if output_parameter_empty?("ip_address")
      end

      def workflow_successful?
        vro_client.token.state == "completed"
      end
    end
  end
end
