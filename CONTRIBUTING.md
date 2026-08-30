# Contributing to kitchen-vro

We'd love to hear from you if this driver doesn't perform the way you expect. Bug reports, feature requests, and pull requests are all welcome.

## Reporting issues

Report bugs and request features on the [issue tracker](https://github.com/test-kitchen/kitchen-vro/issues). For bugs, please include:

- the version of kitchen-vro and Test Kitchen you are using
- your vRO version
- your `kitchen.yml` with credentials and internal hostnames removed
- the input and output parameters of the workflows involved
- the output of the failing command, ideally with `-l debug`

## Development setup

Clone the repository and install the dependencies:

```sh
git clone https://github.com/test-kitchen/kitchen-vro.git
cd kitchen-vro
bundle install
```

## Running the tests

Run the unit tests and the style check together:

```sh
bundle exec rake
```

Run them individually:

```sh
bundle exec rake test    # RSpec unit tests
bundle exec rake style   # Cookstyle / RuboCop
```

To run a single spec file:

```sh
bundle exec rspec spec/vro_spec.rb
```

Many style offenses can be corrected automatically:

```sh
bundle exec cookstyle -a
```

The unit tests stub the vRO client, so they do not contact an appliance and do
not require credentials.

### Manual testing against vRO

Changes that touch workflow execution or parameter handling should also be
exercised against a real appliance, since the stubbed tests cannot catch
API-level regressions.

You will need a create workflow and a destroy workflow meeting the requirements
in the README's Workflow design section. Set the password in the environment
rather than in `kitchen.yml`, and confirm after `kitchen destroy` that the
destroy workflow actually removed the machine — a create that fails partway
through can leave one behind.

## Submitting changes

1. Fork the repository.
2. Create a feature branch off `main`.
3. Make your change, adding or updating tests to cover it.
4. Make sure `bundle exec rake` passes.
5. Push the branch to your fork and open a pull request.

Please keep pull requests focused on a single change — it makes review much
faster. Update the documentation in `README.md` when you add or change a
configuration option, and the Workflow design section when you change what the
driver expects of a workflow.

## Release process

Releases are handled by the maintainers.

1. Update `lib/kitchen/driver/version.rb` with the new version.
2. Update `CHANGELOG.md`.
3. Merge to `main`; the [publish workflow](.github/workflows/publish.yaml) builds
   the gem and pushes it to RubyGems.
