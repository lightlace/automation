# frozen_string_literal: true
require "json"
require "capybara/rspec"
require "capybara/poltergeist"
require "fileutils"

FileUtils.mkdir_p(File.join(File.dirname(__FILE__), "../", "screenshots"))

# Automatically require all files in spec/support directory
Dir[File.join(File.dirname(File.dirname(__FILE__)), "spec", "support", "**", "*.rb")].
  each { |f| require f }

def environment
  env = JSON.parse(File.read(ENV.fetch("ENVIRONMENT", "#{File.join(File.dirname(__FILE__), '../../../')}terraform/environment.json")))
  abort("Please specify kubernetesExternalHost in environment.json") unless env["kubernetesExternalHost"]
  abort("Please specify at least 2 minions in environment.json") if env["minions"].count < 2
  return env
rescue JSON::ParserError
  fail("Invalid JSON format")
rescue
  fail("Please specify ENVIRONMENT to point to a valid environment.json path")
end

def admin_minion
  environment["minions"].detect { |m| m["role"] == "admin" }
end

Capybara.register_driver :poltergeist do |app|
  options = {
    timeout:           180,
    js_errors:         false,
    phantomjs_options: [
      "--proxy-type=none",
      "--load-images=no"
    ]
  }
  # NOTE: uncomment the line below to get more info on the current run.
  # options[:debug] = true
  Capybara::Poltergeist::Driver.new(app, options)
end

Capybara.default_driver = :poltergeist

Capybara.configure do |config|
  config.javascript_driver = :poltergeist
  config.default_max_wait_time = 5
  config.match = :one
  config.exact_options = true
  config.ignore_hidden_elements = true
  config.visible_text_only = true
  config.default_selector = :css

  if admin_minion
    config.app_host = "https://#{admin_minion['fqdn']}"
  else
    config.app_host = "https://localhost"
  end
end

RSpec.configure do |config|
  # rspec-expectations config goes here. You can use an alternate
  # assertion/expectation library such as wrong or the stdlib/minitest
  # assertions if you prefer.
  config.expect_with :rspec do |expectations|
    # This option will default to `true` in RSpec 4. It makes the `description`
    # and `failure_message` of custom matchers include text for helper methods
    # defined using `chain`, e.g.:
    #     be_bigger_than(2).and_smaller_than(4).description
    #     # => "be bigger than 2 and smaller than 4"
    # ...rather than:
    #     # => "be bigger than 2"
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # rspec-mocks config goes here. You can use an alternate test double
  # library (such as bogus or mocha) by changing the `mock_with` option here.
  config.mock_with :rspec do |mocks|
    # Prevents you from mocking or stubbing a method that does not exist on
    # a real object. This is generally recommended, and will default to
    # `true` in RSpec 4.
    mocks.verify_partial_doubles = true
  end

  # This option will default to `:apply_to_host_groups` in RSpec 4 (and will
  # have no way to turn it off -- the option exists only for backwards
  # compatibility in RSpec 3). It causes shared context metadata to be
  # inherited by the metadata hash of host groups and examples, rather than
  # triggering implicit auto-inclusion in groups with matching metadata.
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # fail fast
  config.fail_fast = true

  # Set a timeout around the tests
  timeout = ENV.fetch('TEST_TIMEOUT', 2200).to_i

  config.around(:each) do |test|
    begin
      Timeout::timeout(timeout) { test.run }
    rescue Timeout::Error
      save_screenshot("screenshots/timeout.png", full: true)
      fail
    end
  end

  config.after(:each) do |example|
    if example.exception
      save_screenshot("screenshots/error_state.png", full: true)
    end
  end
end
