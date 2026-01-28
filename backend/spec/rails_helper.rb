# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'

# CRITICAL SAFETY CHECK: Ensure tests NEVER run against development or production
if ENV['RAILS_ENV'] && ENV['RAILS_ENV'] != 'test'
  abort("🚨 DANGER: RAILS_ENV is set to '#{ENV['RAILS_ENV']}'! Tests can ONLY run with RAILS_ENV=test to protect your data!")
end

ENV['RAILS_ENV'] = 'test'  # Force test environment
require_relative '../config/environment'

# Double-check after Rails loads
abort("🚨 DANGER: Tests cannot run in production mode!") if Rails.env.production?
abort("🚨 DANGER: Tests cannot run in development mode!") if Rails.env.development?
require 'rspec/rails'
# Add additional requires below this line. Rails is not loaded until this point!
# Note: factory_bot_rails is auto-loaded by Rails, no need to require manually

# Load support files
Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside

# Ensures that the test database schema matches the current schema file.
# If there are pending migrations it will invoke `db:test:prepare` to
# recreate the test database by loading the schema.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end
RSpec.configure do |config|
  # CRITICAL: Final safety check - ensure we're using test database
  config.before(:suite) do
    db_name = ActiveRecord::Base.connection.current_database
    unless db_name.include?('test')
      abort("🚨 FATAL: Connected to database '#{db_name}' which is NOT a test database! Aborting to protect your data!")
    end
    puts "✅ Safety Check: Using test database '#{db_name}'"
    
    # Configure Sidekiq to run jobs inline during tests (no Redis required)
    require 'sidekiq/testing'
    Sidekiq::Testing.inline!
    puts "✅ Sidekiq configured for inline testing (jobs execute immediately)"
  end

  # Using FactoryBot instead of fixtures

  # Use transactions for speed
  config.use_transactional_fixtures = true

  # Infer spec type from file location
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!

  # FactoryBot shortcuts (Rails automatically loads factories)
  config.include FactoryBot::Syntax::Methods

  # Focused spec runs
  config.filter_run_when_matching :focus

  # Speed and safety tag defaults (exclude slow tests by default)
  config.filter_run_excluding slow: true

  # Randomize order to surface ordering issues
  config.order = :random
  Kernel.srand config.seed
end
