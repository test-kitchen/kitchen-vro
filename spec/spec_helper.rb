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

require "rspec"

require "kitchen"
require "kitchen/driver/vro"
require "kitchen/provisioner/dummy"
require "kitchen/transport/dummy"
require "kitchen/verifier/dummy"

Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |f| require f }

# These specs never talk to a vRO appliance. Everything this driver does is
# turn configuration into vcoworkflows calls and turn workflow output back
# into instance state, so all of it can be exercised against doubles of the
# vcoworkflows API. Anything that genuinely needs an appliance belongs in a
# manual run against a real vRO -- see CONTRIBUTING.md.
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    # `should` has been deprecated since RSpec 3. Only `expect` is available.
    expectations.syntax = :expect
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.syntax = :expect

    # Fail if an example stubs a method the real object does not have. Without
    # this, a rename in lib/ leaves the specs stubbing a method that no longer
    # exists and passing while the driver is broken.
    mocks.verify_partial_doubles = true
  end

  # No `describe` at the top level and no `should` on every object: the specs
  # use `RSpec.describe` and `expect` explicitly.
  config.disable_monkey_patching!

  # Surface deprecations as failures rather than warnings that scroll past.
  config.raise_errors_for_deprecations!

  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.include VroDoubles

  config.filter_run_when_matching :focus

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = "random"
  Kernel.srand config.seed
end
