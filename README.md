# kitchen-vro

[![Gem Version](https://badge.fury.io/rb/kitchen-vro.svg)](https://badge.fury.io/rb/kitchen-vro)

A [Test Kitchen](https://kitchen.ci/) driver that provisions and destroys VMware resources by running [vRealize Orchestrator](https://www.vmware.com/products/vrealize-orchestrator.html) (vRO) workflows, so you can test your cookbooks and infrastructure code against machines built by your own workflows.

Because a vRO workflow can do anything, this driver has to make some assumptions about the ones it calls. Read [Workflow design](#workflow-design) before you start — your create and destroy workflows must expose specific parameters for the driver to work.

> This documentation uses [Cinc Workstation](https://cinc.sh/) and the `cinc` commands throughout. Everything here works identically with Chef Workstation — see [Using with Chef](#using-with-chef).

## Requirements

- Ruby 3.1 or later (already satisfied if you use Cinc Workstation)
- Access to a vRealize Orchestrator appliance
- A **create** workflow and a **destroy** workflow meeting the requirements in [Workflow design](#workflow-design)
- Permission to execute those workflows

## Installation

This driver ships as part of [Cinc Workstation](https://cinc.sh/start/workstation/). If you have Cinc Workstation installed, there is nothing else to install.

To install it into a standalone Ruby:

```sh
gem install kitchen-vro
```

Or with Bundler, add it to your `Gemfile`:

```ruby
gem "kitchen-vro"
```

...then run `bundle install`.

## Quick Start

```yaml
---
driver:
  name: vro
  vro_username: user@domain.com
  vro_password: <%= ENV['VRO_PASSWORD'] %>
  vro_base_url: https://vra.corp.local:8281
  create_workflow_name: Create TK Server
  destroy_workflow_name: Destroy TK Server

provisioner:
  name: cinc_infra

verifier:
  name: cinc_auditor

platforms:
  - name: centos-9

suites:
  - name: default
    run_list:
      - recipe[my_cookbook::default]
```

Then run the full test cycle:

```sh
cinc kitchen test
```

Or step through it:

```sh
cinc kitchen create    # run the create workflow and wait for it
cinc kitchen converge  # apply your cookbook
cinc kitchen verify    # run your tests
cinc kitchen destroy   # run the destroy workflow
```

Keep the password out of `kitchen.yml` by reading it from the environment, as above.

## Configuration

All options below are set under the `driver:` key in `kitchen.yml`, or per platform under `platforms[].driver:`.

### Required

| Option | Default | Description |
| --- | --- | --- |
| `vro_base_url` | *none* | Base URL of the vRO appliance, e.g. `https://vra.corp.local:8281`. Required. |
| `vro_username` | *none* | Username to authenticate with, e.g. `user@domain.com`. Required. |
| `vro_password` | *none* | Password to authenticate with. Required. |
| `create_workflow_name` | *none* | Name of the vRO workflow that creates a server. Required. |
| `destroy_workflow_name` | *none* | Name of the vRO workflow that destroys a server. Required. |

### Workflow selection and parameters

| Option | Default | Description |
| --- | --- | --- |
| `create_workflow_id` | `nil` | Unique ID of the create workflow. Use this when the workflow name is not unique within vRO. |
| `destroy_workflow_id` | `nil` | Unique ID of the destroy workflow. Use this when the workflow name is not unique within vRO. |
| `create_workflow_parameters` | `{}` | Hash of key/value parameters passed to the create workflow. |
| `destroy_workflow_parameters` | `{}` | Hash of key/value parameters passed to the destroy workflow. |

### Connection

| Option | Default | Description |
| --- | --- | --- |
| `request_timeout` | `300` | Seconds to wait for a workflow to finish executing. |
| `vro_disable_ssl_verify` | `false` | Skip TLS certificate validation. Only use this against a lab appliance with a self-signed certificate. |

## Workflow design

There is no limit to what your vRO workflows can do, but they must meet the
following requirements for the driver to drive them.

### Create workflow

- Must have an output parameter called **`ip_address`**, which Test Kitchen
  connects to in order to bootstrap and test the node.
- Must have an output parameter called **`server_id`**, a unique ID for the
  server that was created. The driver passes this to the destroy workflow later.
- Must end with a raised exception if creation did not succeed. The workflow
  status must not be `completed` when it has failed, or the driver will treat a
  failed build as a success.

### Destroy workflow

- Must have an input parameter called **`server_id`**, which the driver
  populates with the value returned by the create workflow.
- Must end with a raised exception if destruction did not succeed. The workflow
  status must not be `completed` when it has failed.

## Examples

### Per-platform workflow parameters

Global settings live under `driver:`, and the parameters that differ per
operating system live under each platform:

```yaml
driver:
  name: vro
  vro_username: user@domain.com
  vro_password: <%= ENV['VRO_PASSWORD'] %>
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

### Workflow names that are not unique

```yaml
driver:
  name: vro
  vro_base_url: https://vra.corp.local:8281
  vro_username: user@domain.com
  vro_password: <%= ENV['VRO_PASSWORD'] %>
  create_workflow_name: Create TK Server
  create_workflow_id: 9f4d4a7e-1234-4b8b-9c2f-77b6c9f0e111
  destroy_workflow_name: Destroy TK Server
  destroy_workflow_id: 3a1b2c3d-5678-4e9f-8a1b-22c4d6e8f0a1
```

### Passing parameters to the destroy workflow

```yaml
driver:
  name: vro
  vro_base_url: https://vra.corp.local:8281
  vro_username: user@domain.com
  vro_password: <%= ENV['VRO_PASSWORD'] %>
  create_workflow_name: Create TK Server
  destroy_workflow_name: Destroy TK Server
  destroy_workflow_parameters:
    force: true
    reason: test-kitchen cleanup
```

### Slow workflows

```yaml
driver:
  name: vro
  vro_base_url: https://vra.corp.local:8281
  vro_username: user@domain.com
  vro_password: <%= ENV['VRO_PASSWORD'] %>
  create_workflow_name: Create TK Server
  destroy_workflow_name: Destroy TK Server
  request_timeout: 1800
```

### Lab appliance with a self-signed certificate

```yaml
driver:
  name: vro
  vro_base_url: https://vro.lab.local:8281
  vro_username: user@lab.local
  vro_password: <%= ENV['VRO_PASSWORD'] %>
  create_workflow_name: Create TK Server
  destroy_workflow_name: Destroy TK Server
  vro_disable_ssl_verify: true
```

## Troubleshooting

**Test Kitchen cannot connect after a successful create.** Check that the create
workflow really does return an `ip_address` output parameter, and that the
address is reachable from where you are running Test Kitchen.

**A failed build is reported as successful.** The workflow finished with status
`completed` despite failing. Raise an exception in the workflow on failure, as
described in [Workflow design](#workflow-design).

**`kitchen destroy` does nothing, or destroys the wrong machine.** The destroy
workflow must take a `server_id` input parameter, and the create workflow must
return a matching `server_id` output.

**The workflow times out.** Increase `request_timeout`; the default is 300
seconds, which is short for a full VM build.

## Using with Chef

This driver is not tied to Cinc. The examples above use Cinc Workstation and the `cinc_infra` provisioner, but the driver works exactly the same with [Chef Workstation](https://www.chef.io/downloads/tools/workstation) — run `kitchen` instead of `cinc kitchen`, and use `chef_infra` instead of `cinc_infra`:

```yaml
provisioner:
  name: chef_infra

verifier:
  name: inspec
```

No driver configuration changes are needed.

## Contributing

We'd love to hear from you if this doesn't perform the way you expect. Bug reports and pull requests are welcome on [GitHub](https://github.com/test-kitchen/kitchen-vro). See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, how to run the tests, and the release process.

## License and Authors

Author: Chef Partner Engineering (<partnereng@chef.io>)

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
