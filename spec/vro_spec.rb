# Encoding: UTF-8
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

require 'spec_helper'
require 'kitchen/driver/vro'
require 'kitchen/provisioner/dummy'
require 'kitchen/transport/dummy'
require 'kitchen/verifier/dummy'

describe Kitchen::Driver::Vro do
  let(:logged_output) { StringIO.new }
  let(:logger)        { Logger.new(logged_output) }
  let(:platform)      { Kitchen::Platform.new(name: 'fake_platform') }
  let(:transport)     { Kitchen::Transport::Dummy.new }
  let(:driver)        { Kitchen::Driver::Vro.new(config) }

  let(:config) do
    {
      vro_username:          'myuser',
      vro_password:          'mypassword',
      vro_base_url:          'https://vra.corp.local:8281',
      create_workflow_name:  'Create Workflow',
      create_workflow_id:    'workflow-1',
      destroy_workflow_name: 'Destroy Workflow',
      destroy_workflow_id:   'workflow-2'
    }
  end

  let(:instance) do
    instance_double(Kitchen::Instance,
                    logger:    logger,
                    transport: transport,
                    platform:  platform,
                    to_str:    'instance_str'
                   )
  end

  before do
    allow(driver).to receive(:instance).and_return(instance)
  end

  describe '#create' do
    context 'when a server already exists' do
      let(:state) { { server_id: 'server-12345' } }

      it 'does not create the server' do
        expect(driver).not_to receive(:execute_create_workflow)

        driver.create(state)
      end
    end

    let(:state) { {} }

    it 'calls the expected methods' do
      expect(driver).to receive(:execute_create_workflow).with(state)
      expect(driver).to receive(:wait_for_server).with(state)

      driver.create(state)
    end
  end

  describe '#destroy' do
    context 'when a server does not exist' do
      let(:state) { {} }

      it 'does not destroy the server' do
        expect(driver).not_to receive(:execute_destroy_workflow)

        driver.destroy(state)
      end
    end

    let(:state) { { server_id: 'server-12345' } }

    it 'calls the expected methods' do
      expect(driver).to receive(:execute_destroy_workflow).with(state)
      driver.destroy(state)
    end
  end

  describe '#vro_config' do
    it 'creates a VcoWorkflows::Config object' do
      expect(VcoWorkflows::Config).to receive(:new).with(url: 'https://vra.corp.local:8281',
                                                         username: 'myuser',
                                                         password: 'mypassword',
                                                         verify_ssl: true)
      driver.vro_config
    end
  end

  describe '#vro_client' do
    let(:vro_config) { double('vro_config') }
    it 'creates a VcoWorkflows::Workflow object' do
      allow(driver).to receive(:workflow_name).and_return('workflow name')
      allow(driver).to receive(:workflow_id).and_return('workflow-12345')
      allow(driver).to receive(:vro_config).and_return(vro_config)

      expect(VcoWorkflows::Workflow).to receive(:new).with('workflow name',
                                                           id: 'workflow-12345',
                                                           config: vro_config)

      driver.vro_client
    end
  end

  describe '#verify_ssl?' do
    context 'when vro_disable_ssl_verify is true' do
      before do
        config[:vro_disable_ssl_verify] = true
      end

      it 'returns false' do
        expect(driver.verify_ssl?).to eq(false)
      end
    end

    context 'when vro_disable_ssl_verify is false' do
      before do
        config[:vro_disable_ssl_verify] = true
      end

      it 'returns true' do
        expect(driver.verify_ssl?).to eq(false)
      end
    end
  end

  describe '#execute_create_workflow' do
    let(:state)      { {} }
    let(:server_id)  { double('server_id', value: 'server-12345') }
    let(:ip_address) { double('ip_address', value: '1.2.3.4') }
    let(:output_parameters) do
      {
        'server_id'  => server_id,
        'ip_address' => ip_address
      }
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

    it 'calls the expected methods' do
      expect(driver).to receive(:set_workflow_vars).with('Create Workflow', 'workflow-1')
      expect(driver).to receive(:set_workflow_parameters).with({})
      expect(driver).to receive(:execute_workflow)
      expect(driver).to receive(:wait_for_workflow)
      expect(driver).to receive(:workflow_successful?)

      driver.execute_create_workflow(state)
    end

    it 'raises an error if the workflow did not complete successfully' do
      allow(driver).to receive(:workflow_successful?).and_return(false)
      expect { driver.execute_create_workflow(state) }.to raise_error(RuntimeError)
    end

    it 'sets the state hash with the proper info' do
      driver.execute_create_workflow(state)

      expect(state[:server_id]).to eq('server-12345')
      expect(state[:hostname]).to eq('1.2.3.4')
    end
  end

  describe '#execute_destroy_workflow' do
    let(:state)      { { server_id: 'server-12345'} }
    let(:vro_client) { double('vro_client') }

    before do
      allow(driver).to receive(:vro_client).and_return(vro_client)
      allow(vro_client).to receive(:parameter)
      allow(driver).to receive(:set_workflow_vars)
      allow(driver).to receive(:set_workflow_parameters)
      allow(driver).to receive(:execute_workflow)
      allow(driver).to receive(:wait_for_workflow)
      allow(driver).to receive(:workflow_successful?).and_return(true)
    end

    it 'calls the expected methods' do
      expect(driver).to receive(:set_workflow_vars).with('Destroy Workflow', 'workflow-2')
      expect(driver).to receive(:set_workflow_parameters).with({})
      expect(vro_client).to receive(:parameter).with('server_id', 'server-12345')
      expect(driver).to receive(:execute_workflow)
      expect(driver).to receive(:wait_for_workflow)
      expect(driver).to receive(:workflow_successful?)

      driver.execute_destroy_workflow(state)
    end

    it 'raises an error if the workflow did not complete successfully' do
      allow(driver).to receive(:workflow_successful?).and_return(false)
      expect { driver.execute_destroy_workflow(state) }.to raise_error(RuntimeError)
    end
  end

  describe '#execute_workflow' do
    let(:vro_client) { double('vro_client') }
    before do
      allow(driver).to receive(:vro_client).and_return(vro_client)
    end

    it 'executes the workflow' do
      expect(vro_client).to receive(:execute)
      driver.execute_workflow
    end

    context 'when execute fails with a RestClient::BadRequest' do
      it 'prints an error with the HTTP response' do
        HTTPResponse = Struct.new(:code, :to_s)
        response = HTTPResponse.new(400, 'an HTTP error occurred')
        exception = RestClient::BadRequest.new
        exception.response = response
        allow(vro_client).to receive(:execute).and_raise(exception)
        expect(driver).to receive(:error).with('The workflow execution request failed: an HTTP error occurred')
        expect { driver.execute_workflow }.to raise_error(RestClient::BadRequest)
      end
    end

    context 'when execute fails with any other exception' do
      it 'prints an error with the exception message' do
        allow(vro_client).to receive(:execute).and_raise(RuntimeError, 'a non-HTTP error occurred')
        expect(driver).to receive(:error).with('The workflow execution request failed: a non-HTTP error occurred')
        expect { driver.execute_workflow }.to raise_error(RuntimeError)
      end
    end
  end

  describe '#wait_for_workflow' do
    let(:vro_client) { double('vro_client') }
    let(:token)      { double('token') }

    before do
      allow(driver).to receive(:vro_client).and_return(vro_client)
      allow(vro_client).to receive(:token).and_return(token)

      # don't actually sleep
      allow(driver).to receive(:sleep)
    end

    context 'when the requests completes normally, 3 loops' do
      it 'only fetches the token 3 times' do
        allow(token).to receive(:alive?).exactly(3).times.and_return(true, true, false)
        expect(vro_client).to receive(:token).exactly(3).times

        driver.wait_for_workflow
      end
    end

    context 'when the request is completed on the first loop' do
      it 'only refreshes the request 1 time' do
        expect(token).to receive(:alive?).once.and_return(false)
        driver.wait_for_workflow
      end
    end

    context 'when the timeout is exceeded' do
      it 'raises a Timeout exception' do
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
        expect { driver.wait_for_workflow }.to raise_error(
          Timeout::Error, 'Workflow did not complete in 300 seconds. ' \
          'Please check the vRO UI for more information.')
      end
    end

    context 'when a non-timeout exception is raised' do
      it 'raises the original exception' do
        allow(vro_client).to receive(:token).and_raise(RuntimeError, 'an error occurred')
        expect { driver.wait_for_workflow }.to raise_error(RuntimeError, 'an error occurred')
      end
    end
  end

  describe '#wait_for_server' do
    let(:connection) { instance.transport.connection(state) }
    let(:state)      { { hostname: 'host1', server_id: 'server-12345' } }

    before do
      allow(transport).to receive(:connection).and_return(connection)
    end

    it 'calls wait_until_ready on the transport connection' do
      expect(connection).to receive(:wait_until_ready)
      driver.wait_for_server(state)
    end

    it 'destroys the server if the server failed to become ready' do
      allow(connection).to receive(:wait_until_ready).and_raise(RuntimeError)
      expect(driver).to receive(:destroy).with(state)
      expect { driver.wait_for_server(state) }.to raise_error(RuntimeError)
    end
  end

  describe '#set_workflow_parameters' do
    let(:vro_client) { double('vro_client') }
    let(:params)     { { key1: 'value1', key2: 'value2' } }

    it 'sets parameters on the client' do
      allow(driver).to receive(:vro_client).and_return(vro_client)
      expect(vro_client).to receive(:parameter).with('key1', 'value1')
      expect(vro_client).to receive(:parameter).with('key2', 'value2')

      driver.set_workflow_parameters(params)
    end
  end
end
