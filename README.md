# kitchen-vro

A driver to allow Test Kitchen to consume VMware resources provisioned by
way of vRealize Orchestrator workflows.

vRO allows you to create any workflow you can imagine, but our plugin needs
to make some assumptions about the workflows you design in order to properly
provision and destroy resources.  Therefore, please pay special attention to
the **Workflow Design** section below and ensure your workflows adhere to
these design requirements.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'kitchen-vro'
```

And then execute:

```shell
bundle
```

Or install it yourself as:

```shell
gem install kitchen-vro
```

Or even better, install it via ChefDK:

```shell
chef gem install kitchen-vro
```

## Usage

After installing the gem as described above, edit your .kitchen.yml file to set the driver to 'vro' and supply your login credentials:

```yaml
driver:
  name: vro
  vro_username: user@domain.com
  vro_password: MyS33kretPassword
  vro_base_url: https://vra.corp.local:8281
```

Additionally, the following parameters are required, either globally or per-platform:

* **create_workflow_name**: The name of the vRO workflow to execute to create a server.
* **destroy_workflow_name**: The name of the vRO workflow to execute to destroy a server.

There are a number of optional parameters you can configure as well:

* **create_workflow_id**: If your create workflow name is not unique within vRO, you can use
   this parameter to specify the workflow unique ID.
* **destroy_workflow_id**: If your destroy workflow name is not unique within vRO, you can use
   this parameter to specify the workflow unique ID.
* **create_workflow_parameters**: A hash of key-value pairs of parameters to pass to your
   create workflow.
* **destroy_workflow_parameters**: A hash of key-value pairs of parameters to pass to your
   destroy workflow.
* **request_timeout**: Number of seconds to wait for a vRO workflow to execute.  Default: 300
* **vro_disable_ssl_verify**: Disable SSL validation.  Default: false

An example `.kitchen.yml` that uses a combination of global and per-platform
settings might look like this:

```yaml
driver:
  name: vro
  vro_username: user@domain.com
  vro_password: MyS33kretPassword
  vro_base_url: https://vra.corp.local:8281
  create_workflow_name: Create TK Server
  destroy_workflow_name: Destroy TK Server

platforms:
  - name: centos
    driver:
      create_workflow_parameters:
        os_name: centos
        os_version: 6.7
  - name: windows
    driver:
      create_workflow_parameters:
        os_name: windows
        os_version: server2012
        cpus: 4
        memory: 4096
```

## Workflow Design

There are no limits as to what you can do with your vRO workflows!  However,
they must meet the following requirements.

### Create Workflow

* Must contain an output parameter called `ip_address` that Test Kitchen can
   connect to in order to bootstrap and test your node.
* Must contain an output parameter called `server_id` that is a unique ID of
   the server created.  Test Kitchen will provide this value to the Destroy
   Workflow in order to request the destruction of the server once testing is
   complete.
* Must end the workflow with a raised exception if the creation did not
   succeed.  The workflow status must not be 'completed.'

### Destroy Workflow

* Must contain an input parameter called `server_id` that Test Kitchen will
   populate with the unique ID returned from the Create Workflow output.
* Must end the workflow with a raised exception if the creation did not
     succeed.  The workflow status must not be 'completed.'

## License and Authors

Author:: Chef Partner Engineering (<partnereng@chef.io>)

Copyright:: Copyright (c) 2015 Chef Software, Inc.

License:: Apache License, Version 2.0

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the License at

```text
http://www.apache.org/licenses/LICENSE-2.0
```

Unless required by applicable law or agreed to in writing, software distributed under the
License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
either express or implied. See the License for the specific language governing permissions
and limitations under the License.

## Contributing

We'd love to hear from you if this doesn't perform in the manner you expect. Please log a GitHub issue, or even better, submit a Pull Request with a fix!

1. Fork it ( <https://github.com/chef-partners/kitchen-vro/fork> )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
