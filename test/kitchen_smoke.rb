#!/usr/bin/env ruby
#
# License:: Apache License, Version 2.0
#
# Exercises kitchen-vro through Test Kitchen rather than through RSpec.
#
# The unit tests instantiate Kitchen::Driver::Vro directly, so they never
# prove that Test Kitchen can find the plugin by the name people put in their
# kitchen.yml, that the gemspec ships the files it needs, that required_config
# and default_config are wired up, or that a realistic kitchen.yml parses into
# the configuration the README promises.
#
# None of this needs a vRO appliance: building instances and running
# `kitchen list` / `kitchen diagnose` all stop short of talking to one.
#
# Run it with `bundle exec rake integration`.

require "open3"
require "rbconfig"
require "kitchen"

ROOT     = File.expand_path("..", __dir__).freeze
FIXTURES = File.join(__dir__, "fixtures").freeze

# Every instance kitchen.yml is expected to produce, in order.
INSTANCES = %w{
  default-defaults
  default-workflow-ids
  default-workflow-parameters
  default-slow-workflows
  default-self-signed-cert
}.freeze

# The defaults the README documents, as the driver should resolve them.
DOCUMENTED_DEFAULTS = {
  request_timeout: 300,
  vro_disable_ssl_verify: false,
  create_workflow_id: nil,
  destroy_workflow_id: nil,
  create_workflow_parameters: {},
  destroy_workflow_parameters: {},
}.freeze

@failures = []

# Builds the Test Kitchen instances a config file describes, the same way the
# `kitchen` command does.
#
# @param config [String] path to a kitchen.yml
# @return [Array<Kitchen::Instance>]
def instances_for(config)
  Kitchen::Config.new(
    kitchen_root: ROOT,
    loader: Kitchen::Loader::YAML.new(project_config: config)
  ).instances
end

# The `kitchen` executable from the bundle, run under the Ruby running this
# script. Resolving it through Gem rather than PATH keeps the check honest --
# on a machine with a second Test Kitchen installed system-wide, a bare
# `kitchen` could easily be a different one than the gem under test.
KITCHEN_BIN = [
  RbConfig.ruby,
  Gem.bin_path("test-kitchen", "kitchen"),
].freeze

# Runs a `kitchen` subcommand and reports whether it succeeded.
#
# @return [Array(String, Boolean)] combined output, and whether it succeeded
def kitchen(*args)
  output, status = Open3.capture2e(*KITCHEN_BIN, *args, chdir: ROOT)
  [output, status.success?]
end

# Records the result of one check. The block returns nil when the check
# passes, or a string explaining the failure.
def check(description)
  problem = yield
  if problem
    @failures << "#{description}: #{problem}"
    puts "  not ok  #{description}"
  else
    puts "  ok      #{description}"
  end
rescue => e
  @failures << "#{description}: raised #{e.class}: #{e.message}"
  puts "  not ok  #{description}"
end

puts "Test Kitchen loads and configures the driver"

instances = instances_for(File.join(ROOT, "kitchen.yml"))

check "every configured instance is built" do
  found = instances.map(&:name)
  "expected #{INSTANCES.inspect}, got #{found.inspect}" unless found == INSTANCES
end

check "the plugin is discovered by the name people write in kitchen.yml" do
  plugin = instances.first.driver.diagnose_plugin
  next "resolved to #{plugin[:class]}" unless plugin[:class] == "Kitchen::Driver::Vro"
  next "reported api_version #{plugin[:api_version]}" unless plugin[:api_version] == 2

  "reported version #{plugin[:version]}" unless plugin[:version] == Kitchen::Driver::VRO_VERSION
end

DOCUMENTED_DEFAULTS.each do |option, expected|
  check "#{option} defaults to #{expected.inspect}, as documented" do
    actual = instances.first.driver[option]
    "resolved to #{actual.inspect}" unless actual == expected
  end
end

check "workflow ids set in kitchen.yml reach the driver" do
  driver = instances[1].driver
  next "create_workflow_id was #{driver[:create_workflow_id].inspect}" unless
    driver[:create_workflow_id] == "9f4d4a7e-1234-4b8b-9c2f-77b6c9f0e111"

  "destroy_workflow_id was #{driver[:destroy_workflow_id].inspect}" unless
    driver[:destroy_workflow_id] == "3a1b2c3d-5678-4e9f-8a1b-22c4d6e8f0a1"
end

check "workflow parameters survive the trip through kitchen.yml" do
  driver = instances[2].driver
  expected = { os_name: "centos", os_version: "9", cpus: 4, memory: 4096 }
  next "create_workflow_parameters resolved to #{driver[:create_workflow_parameters].inspect}" unless
    driver[:create_workflow_parameters] == expected

  "destroy_workflow_parameters resolved to #{driver[:destroy_workflow_parameters].inspect}" unless
    driver[:destroy_workflow_parameters] == { force: true, reason: "test-kitchen cleanup" }
end

check "a per-platform request_timeout overrides the default" do
  actual = instances[3].driver[:request_timeout]
  "resolved to #{actual.inspect}" unless actual == 1800
end

check "vro_disable_ssl_verify turns TLS verification off" do
  driver = instances[4].driver
  "verify_ssl? was #{driver.verify_ssl?.inspect}" if driver.verify_ssl?
end

check "a config missing a required option is rejected" do
  instances_for(File.join(FIXTURES, "kitchen.missing-required-config.yml"))
  "Test Kitchen accepted a config with no create_workflow_name"
rescue Kitchen::UserError => e
  "the error did not name the missing option: #{e.message}" unless
    e.message.include?("create_workflow_name")
end

puts "\nThe kitchen command line works against the driver"

list, listed = kitchen("list", "--bare")

check "kitchen list succeeds" do
  next "kitchen list failed:\n#{list}" unless listed

  "listed #{list.split("\n").length} instances" unless list.split("\n").length == INSTANCES.length
end

diagnose, diagnosed = kitchen("diagnose", "--all")

check "kitchen diagnose succeeds" do
  next "kitchen diagnose failed:\n#{diagnose}" unless diagnosed

  "the vRO driver was missing from the plugin list" unless diagnose.include?("Kitchen::Driver::Vro")
end

if @failures.empty?
  puts "\nAll checks passed."
else
  puts "\n#{@failures.length} check(s) failed:"
  @failures.each { |failure| puts "  - #{failure}" }
  exit 1
end
