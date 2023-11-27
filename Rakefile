require "bundler/gem_tasks"
require "rspec/core/rake_task"

begin
  require "chefstyle"
  require "rubocop/rake_task"
  RuboCop::RakeTask.new(:style) do |task|
    task.options += ["--display-cop-names", "--no-color"]
  end
rescue LoadError
  puts "chefstyle is not available. (sudo) gem install chefstyle to do style checking."
end

RSpec::Core::RakeTask.new(:test)

task default: %i{test style}
