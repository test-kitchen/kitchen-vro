#
# Authors:: Chef Partner Engineering (<partnereng@chef.io>)
# Copyright:: Copyright (c) 2015 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

RSpec.shared_examples "output parameters that are missing a required key" do
  it "raises an exception" do
    allow(driver).to receive(:output_parameters).and_return(output_parameters)

    expect { driver.validate_create_output_parameters! }.to raise_error(
      RuntimeError,
      "The workflow output did not contain a server_id and ip_address parameter."
    )
  end
end

RSpec.describe Kitchen::Driver::Vro do
  let(:logged_output) { StringIO.new }
  let(:logger)        { Logger.new(logged_output) }
  let(:platform)      { Kitchen::Platform.new(name: "fake_platform") }
  let(:transport)     { Kitchen::Transport::Dummy.new }
  let(:driver)        { described_class.new(config) }

  let(:config) do
    {
      vro_username: "myuser",
      vro_password: "mypassword",
      vro_base_url: "https://vra.corp.local:8281",
      create_workflow_name: "Create Workflow",
      create_workflow_id: "workflow-1",
      destroy_workflow_name: "Destroy Workflow",
      destroy_workflow_id: "workflow-2",
    }
  end

  let(:instance) do
    instance_double(Kitchen::Instance,
      logger: logger,
      transport: transport,
      platform: platform,
      to_str: "instance_str")
  end

  before do
    allow(driver).to receive(:instance).and_return(instance)
  end

  describe "plugin metadata" do
    it "is a Test Kitchen driver" do
      expect(driver).to be_a(Kitchen::Driver::Base)
    end

    it "shows up as vRO in kitchen list" do
      expect(driver.name).to eq("vRO")
    end

    it "reports its own gem version to kitchen diagnose" do
      expect(driver.diagnose_plugin[:version]).to eq(Kitchen::Driver::VRO_VERSION)
    end

    it "speaks version 2 of the driver API" do
      expect(driver.diagnose_plugin[:api_version]).to eq(2)
    end
  end

  describe "configuration" do
    it "verifies TLS by default" do
      expect(driver[:vro_disable_ssl_verify]).to be false
    end

    it "defaults to a 300 second workflow timeout" do
      expect(driver[:request_timeout]).to eq(300)
    end

    it "defaults both workflow ids to nil so the name is used alone" do
      config.delete(:create_workflow_id)
      config.delete(:destroy_workflow_id)

      expect(driver[:create_workflow_id]).to be_nil
      expect(driver[:destroy_workflow_id]).to be_nil
    end

    it "defaults both workflow parameter sets to empty" do
      expect(driver[:create_workflow_parameters]).to eq({})
      expect(driver[:destroy_workflow_parameters]).to eq({})
    end

    required = %i{vro_username vro_password vro_base_url create_workflow_name destroy_workflow_name}

    required.each do |key|
      it "refuses to run without #{key}" do
        config.delete(key)

        expect { driver.finalize_config!(instance) }
          .to raise_error(Kitchen::UserError, /#{key}/)
      end
    end

    it "accepts a configuration that supplies every required key" do
      expect { driver.finalize_config!(instance) }.not_to raise_error
    end
  end

  describe "#vro_config" do
    it "passes the configured endpoint and credentials through to vcoworkflows" do
      vro_config = driver.vro_config

      expect(vro_config).to be_a(VcoWorkflows::Config)
      expect(vro_config.username).to eq("myuser")
      expect(vro_config.password).to eq("mypassword")
      expect(vro_config.url).to start_with("https://vra.corp.local:8281")
    end

    it "asks vcoworkflows to verify TLS by default" do
      expect(driver.vro_config.verify_ssl).to be true
    end

    it "asks vcoworkflows to skip TLS verification when it is disabled" do
      config[:vro_disable_ssl_verify] = true

      expect(driver.vro_config.verify_ssl).to be false
    end

    it "builds the config only once" do
      expect(driver.vro_config).to equal(driver.vro_config)
    end
  end

  describe "#verify_ssl?" do
    it "is false when vro_disable_ssl_verify is true" do
      config[:vro_disable_ssl_verify] = true

      expect(driver.verify_ssl?).to be false
    end

    it "is true when vro_disable_ssl_verify is false" do
      config[:vro_disable_ssl_verify] = false

      expect(driver.verify_ssl?).to be true
    end
  end

  describe "#vro_client" do
    let(:vro_config) { instance_double(VcoWorkflows::Config) }

    before do
      allow(driver).to receive(:vro_config).and_return(vro_config)
    end

    it "creates a VcoWorkflows::Workflow for the current workflow" do
      driver.set_workflow_vars("workflow name", "workflow-12345")

      expect(VcoWorkflows::Workflow).to receive(:new)
        .with("workflow name", id: "workflow-12345", config: vro_config)

      driver.vro_client
    end

    it "builds the client only once" do
      allow(VcoWorkflows::Workflow).to receive(:new).and_return(workflow_client)

      driver.vro_client
      driver.vro_client

      expect(VcoWorkflows::Workflow).to have_received(:new).once
    end
  end

  describe "#set_workflow_vars" do
    it "points the driver at the named workflow" do
      driver.set_workflow_vars("Some Workflow", "workflow-9")

      expect(driver.workflow_name).to eq("Some Workflow")
      expect(driver.workflow_id).to eq("workflow-9")
    end

    it "accepts a nil id for a workflow addressed by name alone" do
      driver.set_workflow_vars("Some Workflow", nil)

      expect(driver.workflow_id).to be_nil
    end

    it "discards the memoized client so the next call builds a new one" do
      first  = workflow_client
      second = workflow_client
      allow(driver).to receive(:vro_config).and_return(instance_double(VcoWorkflows::Config))
      allow(VcoWorkflows::Workflow).to receive(:new).and_return(first, second)

      driver.set_workflow_vars("Create Workflow", "workflow-1")
      expect(driver.vro_client).to equal(first)

      driver.set_workflow_vars("Destroy Workflow", "workflow-2")
      expect(driver.vro_client).to equal(second)
    end
  end

  describe "#create" do
    let(:state) { {} }

    it "runs the create workflow and then waits for the server" do
      expect(driver).to receive(:execute_create_workflow).with(state).ordered
      expect(driver).to receive(:wait_for_server).with(state).ordered

      driver.create(state)
    end

    it "does nothing when state already names a server" do
      state[:server_id] = "server-12345"

      expect(driver).not_to receive(:execute_create_workflow)
      expect(driver).not_to receive(:wait_for_server)

      driver.create(state)
    end

    context "with the vRO API stubbed end to end" do
      let(:token) do
        workflow_token(output: { "server_id" => "server-12345", "ip_address" => "1.2.3.4" })
      end
      let(:client)     { workflow_client(token: token) }
      let(:connection) { transport.connection(state) }

      before do
        allow(VcoWorkflows::Workflow).to receive(:new).and_return(client)
        allow(transport).to receive(:connection).and_return(connection)
        allow(connection).to receive(:wait_until_ready)
      end

      it "records the server the workflow reported" do
        driver.create(state)

        expect(state[:server_id]).to eq("server-12345")
        expect(state[:hostname]).to eq("1.2.3.4")
      end

      it "waits for the transport to accept a connection" do
        driver.create(state)

        expect(connection).to have_received(:wait_until_ready)
      end

      it "asks vRO for the configured create workflow" do
        driver.create(state)

        expect(VcoWorkflows::Workflow).to have_received(:new)
          .with("Create Workflow", hash_including(id: "workflow-1"))
      end

      it "sends the configured create parameters to the workflow" do
        config[:create_workflow_parameters] = { os_name: "centos", cpus: 4 }

        driver.create(state)

        expect(client).to have_received(:parameter).with("os_name", "centos")
        expect(client).to have_received(:parameter).with("cpus", 4)
      end
    end
  end

  describe "#destroy" do
    let(:state) { { server_id: "server-12345", hostname: "1.2.3.4" } }

    it "runs the destroy workflow" do
      expect(driver).to receive(:execute_destroy_workflow).with(state)

      driver.destroy(state)
    end

    it "does nothing when state does not name a server" do
      expect(driver).not_to receive(:execute_destroy_workflow)

      driver.destroy({})
    end

    context "with the vRO API stubbed end to end" do
      let(:client) { workflow_client }

      before do
        allow(VcoWorkflows::Workflow).to receive(:new).and_return(client)
      end

      it "asks vRO for the configured destroy workflow" do
        driver.destroy(state)

        expect(VcoWorkflows::Workflow).to have_received(:new)
          .with("Destroy Workflow", hash_including(id: "workflow-2"))
      end

      it "hands the stored server id to the destroy workflow" do
        driver.destroy(state)

        expect(client).to have_received(:parameter).with("server_id", "server-12345")
      end

      it "sends the configured destroy parameters to the workflow" do
        config[:destroy_workflow_parameters] = { force: true }

        driver.destroy(state)

        expect(client).to have_received(:parameter).with("force", true)
      end
    end
  end

  describe "#execute_create_workflow" do
    let(:state) { {} }
    let(:output_parameters) do
      workflow_output("server_id" => "server-12345", "ip_address" => "1.2.3.4")
    end

    before do
      allow(driver).to receive(:set_workflow_vars)
      allow(driver).to receive(:set_workflow_parameters)
      allow(driver).to receive(:execute_workflow)
      allow(driver).to receive(:wait_for_workflow)
      allow(driver).to receive(:workflow_successful?).and_return(true)
      allow(driver).to receive(:validate_create_output_parameters!)
      allow(driver).to receive(:output_parameters).and_return(output_parameters)
    end

    it "selects the create workflow and submits it" do
      expect(driver).to receive(:set_workflow_vars).with("Create Workflow", "workflow-1")
      expect(driver).to receive(:set_workflow_parameters).with({})
      expect(driver).to receive(:execute_workflow)
      expect(driver).to receive(:wait_for_workflow)
      expect(driver).to receive(:workflow_successful?)

      driver.execute_create_workflow(state)
    end

    it "raises an error if the workflow did not complete successfully" do
      allow(driver).to receive(:workflow_successful?).and_return(false)

      expect { driver.execute_create_workflow(state) }.to raise_error(RuntimeError)
    end

    it "does not validate the output of a workflow that failed" do
      allow(driver).to receive(:workflow_successful?).and_return(false)

      expect(driver).not_to receive(:validate_create_output_parameters!)

      expect { driver.execute_create_workflow(state) }.to raise_error(RuntimeError)
    end

    it "sets the state hash with the proper info" do
      driver.execute_create_workflow(state)

      expect(state[:server_id]).to eq("server-12345")
      expect(state[:hostname]).to eq("1.2.3.4")
    end

    it "leaves state untouched when the output does not validate" do
      allow(driver).to receive(:validate_create_output_parameters!)
        .and_raise(RuntimeError, "The server_id parameter was empty.")

      expect { driver.execute_create_workflow(state) }.to raise_error(RuntimeError)
      expect(state).to be_empty
    end
  end

  describe "#execute_destroy_workflow" do
    let(:state)      { { server_id: "server-12345" } }
    let(:vro_client) { workflow_client }

    before do
      allow(driver).to receive(:vro_client).and_return(vro_client)
      allow(driver).to receive(:set_workflow_vars)
      allow(driver).to receive(:set_workflow_parameters)
      allow(driver).to receive(:execute_workflow)
      allow(driver).to receive(:wait_for_workflow)
      allow(driver).to receive(:workflow_successful?).and_return(true)
    end

    it "selects the destroy workflow and submits it with the server id" do
      expect(driver).to receive(:set_workflow_vars).with("Destroy Workflow", "workflow-2")
      expect(driver).to receive(:set_workflow_parameters).with({})
      expect(vro_client).to receive(:parameter).with("server_id", "server-12345")
      expect(driver).to receive(:execute_workflow)
      expect(driver).to receive(:wait_for_workflow)
      expect(driver).to receive(:workflow_successful?)

      driver.execute_destroy_workflow(state)
    end

    it "raises an error if the workflow did not complete successfully" do
      allow(driver).to receive(:workflow_successful?).and_return(false)

      expect { driver.execute_destroy_workflow(state) }.to raise_error(RuntimeError)
    end
  end

  describe "#execute_workflow" do
    let(:vro_client) { workflow_client }

    before do
      allow(driver).to receive(:vro_client).and_return(vro_client)
    end

    it "executes the workflow" do
      expect(vro_client).to receive(:execute)

      driver.execute_workflow
    end

    context "when execute fails with a RestClient::BadRequest" do
      let(:exception) do
        RestClient::BadRequest.new.tap do |e|
          e.response = "an HTTP error occurred"
        end
      end

      it "logs the HTTP response body, which is where vRO puts the reason" do
        allow(vro_client).to receive(:execute).and_raise(exception)

        expect(driver).to receive(:error)
          .with("The workflow execution request failed: an HTTP error occurred")

        expect { driver.execute_workflow }.to raise_error(RestClient::BadRequest)
      end
    end

    context "when execute fails with any other exception" do
      it "logs the exception message and re-raises" do
        allow(vro_client).to receive(:execute)
          .and_raise(RuntimeError, "a non-HTTP error occurred")

        expect(driver).to receive(:error)
          .with("The workflow execution request failed: a non-HTTP error occurred")

        expect { driver.execute_workflow }.to raise_error(RuntimeError, "a non-HTTP error occurred")
      end
    end
  end

  describe "#wait_for_workflow" do
    let(:token)      { workflow_token(alive: [true, true, false]) }
    let(:vro_client) { workflow_client(token: token) }

    before do
      allow(driver).to receive(:vro_client).and_return(vro_client)

      # Don't actually sleep between polls.
      allow(driver).to receive(:sleep)
    end

    it "polls until the token is no longer alive" do
      driver.wait_for_workflow

      expect(token).to have_received(:alive?).exactly(3).times
    end

    it "re-reads the token on every poll rather than caching it" do
      driver.wait_for_workflow

      expect(vro_client).to have_received(:token).exactly(3).times
    end

    it "waits two seconds between polls" do
      driver.wait_for_workflow

      expect(driver).to have_received(:sleep).with(2).twice
    end

    it "does not sleep when the workflow is already finished on the first poll" do
      allow(token).to receive(:alive?).and_return(false)

      driver.wait_for_workflow

      expect(driver).not_to have_received(:sleep)
    end

    context "when the timeout is exceeded" do
      it "raises a Timeout error naming the configured timeout" do
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

        expect { driver.wait_for_workflow }.to raise_error(
          Timeout::Error, "Workflow did not complete in 300 seconds. " \
          "Please check the vRO UI for more information."
        )
      end

      it "reports a non-default request_timeout" do
        config[:request_timeout] = 30
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

        expect { driver.wait_for_workflow }
          .to raise_error(Timeout::Error, /did not complete in 30 seconds/)
      end

      it "actually gives up once the configured timeout elapses" do
        config[:request_timeout] = 0.05
        allow(token).to receive(:alive?).and_return(true)
        allow(driver).to receive(:sleep) { Kernel.sleep(0.01) }

        expect { driver.wait_for_workflow }.to raise_error(Timeout::Error)
      end
    end

    it "lets a non-timeout exception through untouched" do
      allow(vro_client).to receive(:token).and_raise(RuntimeError, "an error occurred")

      expect { driver.wait_for_workflow }.to raise_error(RuntimeError, "an error occurred")
    end
  end

  describe "#wait_for_server" do
    let(:state)      { { hostname: "host1", server_id: "server-12345" } }
    let(:connection) { transport.connection(state) }

    before do
      allow(transport).to receive(:connection).and_return(connection)
    end

    it "calls wait_until_ready on the transport connection" do
      expect(connection).to receive(:wait_until_ready)

      driver.wait_for_server(state)
    end

    it "destroys the server if the server failed to become ready" do
      allow(connection).to receive(:wait_until_ready).and_raise(RuntimeError)

      expect(driver).to receive(:destroy).with(state)

      expect { driver.wait_for_server(state) }.to raise_error(RuntimeError)
    end

    it "re-raises the original connection failure" do
      allow(connection).to receive(:wait_until_ready)
        .and_raise(Kitchen::Transport::TransportFailed, "connection refused")
      allow(driver).to receive(:destroy)

      expect { driver.wait_for_server(state) }
        .to raise_error(Kitchen::Transport::TransportFailed, "connection refused")
    end
  end

  describe "#set_workflow_parameters" do
    let(:vro_client) { workflow_client }

    before do
      allow(driver).to receive(:vro_client).and_return(vro_client)
    end

    it "sets parameters on the client" do
      expect(vro_client).to receive(:parameter).with("key1", "value1")
      expect(vro_client).to receive(:parameter).with("key2", "value2")

      driver.set_workflow_parameters(key1: "value1", key2: "value2")
    end

    it "stringifies symbol keys, which is how they arrive from kitchen.yml" do
      expect(vro_client).to receive(:parameter).with("os_version", "9")

      driver.set_workflow_parameters(os_version: "9")
    end

    it "passes non-string values through untouched" do
      expect(vro_client).to receive(:parameter).with("cpus", 4)
      expect(vro_client).to receive(:parameter).with("ha", true)

      driver.set_workflow_parameters("cpus" => 4, "ha" => true)
    end

    it "does nothing when there are no parameters" do
      expect(vro_client).not_to receive(:parameter)

      driver.set_workflow_parameters({})
    end
  end

  describe "#output_parameters" do
    let(:token)      { workflow_token(output: { "server_id" => "server-12345" }) }
    let(:vro_client) { workflow_client(token: token) }

    before do
      allow(driver).to receive(:vro_client).and_return(vro_client)
    end

    it "returns the output parameters from the workflow token" do
      expect(driver.output_parameters.keys).to eq(["server_id"])
    end

    it "reads them from the token only once" do
      driver.output_parameters
      driver.output_parameters

      expect(token).to have_received(:output_parameters).once
    end
  end

  describe "#output_parameter_value" do
    it "returns the value vRO reported" do
      allow(driver).to receive(:output_parameters)
        .and_return(workflow_output("test_key" => "test_value"))

      expect(driver.output_parameter_value("test_key")).to eq("test_value")
    end

    it "stringifies a value that vRO returned as a number" do
      allow(driver).to receive(:output_parameters)
        .and_return(workflow_output("server_id" => 12_345))

      expect(driver.output_parameter_value("server_id")).to eq("12345")
    end

    it "returns an empty string for a parameter vRO left unset" do
      allow(driver).to receive(:output_parameters)
        .and_return(workflow_output("ip_address" => nil))

      expect(driver.output_parameter_value("ip_address")).to eq("")
    end
  end

  describe "#output_parameter_empty?" do
    it "is false when the value is neither nil nor empty" do
      allow(driver).to receive(:output_parameter_value).with("test_key").and_return("test_value")

      expect(driver.output_parameter_empty?("test_key")).to be false
    end

    it "is true when the value is nil" do
      allow(driver).to receive(:output_parameter_value).with("test_key").and_return(nil)

      expect(driver.output_parameter_empty?("test_key")).to be true
    end

    it "is true when the value is empty" do
      allow(driver).to receive(:output_parameter_value).with("test_key").and_return("")

      expect(driver.output_parameter_empty?("test_key")).to be true
    end
  end

  describe "#validate_create_output_parameters!" do
    context "when the output parameters do not include server_id and ip_address" do
      let(:output_parameters) { {} }

      it_behaves_like "output parameters that are missing a required key"
    end

    context "when the output parameters do not include server_id" do
      let(:output_parameters) { workflow_output("ip_address" => "1.2.3.4") }

      it_behaves_like "output parameters that are missing a required key"
    end

    context "when the output parameters do not include ip_address" do
      let(:output_parameters) { workflow_output("server_id" => "server-12345") }

      it_behaves_like "output parameters that are missing a required key"
    end

    it "raises when server_id is empty" do
      allow(driver).to receive(:output_parameters)
        .and_return(workflow_output("server_id" => "", "ip_address" => "1.2.3.4"))

      expect { driver.validate_create_output_parameters! }
        .to raise_error(RuntimeError, "The server_id parameter was empty.")
    end

    it "raises when ip_address is empty" do
      allow(driver).to receive(:output_parameters)
        .and_return(workflow_output("server_id" => "server-12345", "ip_address" => ""))

      expect { driver.validate_create_output_parameters! }
        .to raise_error(RuntimeError, "The ip_address parameter was empty.")
    end

    it "accepts output that names both a server and an address" do
      allow(driver).to receive(:output_parameters)
        .and_return(workflow_output("server_id" => "server-12345", "ip_address" => "1.2.3.4"))

      expect { driver.validate_create_output_parameters! }.not_to raise_error
    end
  end

  describe "#workflow_successful?" do
    it "is true when vRO reports the run completed" do
      allow(driver).to receive(:vro_client)
        .and_return(workflow_client(token: workflow_token(state: "completed")))

      expect(driver.workflow_successful?).to be true
    end

    it "is false for any other state" do
      allow(driver).to receive(:vro_client)
        .and_return(workflow_client(token: workflow_token(state: "failed")))

      expect(driver.workflow_successful?).to be false
    end
  end
end
