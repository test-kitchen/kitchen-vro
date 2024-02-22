lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "kitchen/driver/vro_version"

Gem::Specification.new do |spec|
  spec.name          = "kitchen-vro"
  spec.version       = Kitchen::Driver::VRO_VERSION
  spec.authors       = ["Test Kitchen Team"]
  spec.email         = ["help@sous-chefs.org"]
  spec.summary       = "A Test Kitchen driver for VMware vRealize Orchestrator (vRO)"
  spec.description   = spec.summary
  spec.homepage      = "https://https://github.com/test-kitchen/kitchen-vro"
  spec.license       = "Apache 2.0"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = []
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "test-kitchen", ">= 1.4", "< 4"
  spec.add_dependency "vcoworkflows", "~> 0.2"
end
