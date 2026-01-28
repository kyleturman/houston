#!/usr/bin/env ruby
# App Store Connect API Helper
# Uses JWT gem for proper ES256 token generation (avoids Ruby 3.4 OpenSSL issues)

require 'net/http'
require 'json'
require 'jwt'
require 'openssl'
require 'uri'
require 'yaml'

class AppStoreConnectAPI
  BASE_URL = "https://api.appstoreconnect.apple.com/v1"

  def initialize(key_id:, issuer_id:, key_path:)
    @key_id = key_id
    @issuer_id = issuer_id
    @private_key = OpenSSL::PKey::EC.new(File.read(key_path))
  end

  # Generate JWT token for API authentication
  def generate_token
    header = { kid: @key_id }
    payload = {
      iss: @issuer_id,
      iat: Time.now.to_i,
      exp: Time.now.to_i + 20 * 60, # 20 minutes
      aud: "appstoreconnect-v1"
    }
    JWT.encode(payload, @private_key, 'ES256', header)
  end

  # Get app info
  def get_app(app_id)
    request(:get, "/apps/#{app_id}")
  end

  # List builds for an app
  def list_builds(app_id, version: nil, build_number: nil)
    filter = []
    filter << "filter[app]=#{app_id}"
    filter << "filter[version]=#{version}" if version
    filter << "filter[buildNumber]=#{build_number}" if build_number
    filter << "sort=-uploadedDate"
    filter << "limit=10"

    request(:get, "/builds?#{filter.join('&')}")
  end

  # Get build by version and build number (polls until found or timeout)
  def get_build(app_id, version, build_number, timeout: 600)
    start_time = Time.now

    loop do
      builds = list_builds(app_id, version: version, build_number: build_number)

      if builds && builds["data"]&.any?
        build = builds["data"].first
        processing_state = build.dig("attributes", "processingState")

        # Return if build is processed
        return build if processing_state == "VALID"

        # Show processing status
        puts "  Build processing: #{processing_state}..."
      else
        puts "  Waiting for build to appear..."
      end

      # Check timeout
      elapsed = Time.now - start_time
      if elapsed > timeout
        raise "Timeout waiting for build to process (#{timeout}s)"
      end

      sleep 30
    end
  end

  # List beta groups
  def list_beta_groups(app_id)
    request(:get, "/apps/#{app_id}/betaGroups")
  end

  # Get or create beta group
  def get_or_create_beta_group(app_id, group_name)
    # Check if group exists
    groups = list_beta_groups(app_id)
    existing = groups["data"]&.find { |g| g.dig("attributes", "name") == group_name }

    return existing if existing

    # Create group
    puts "  Creating beta group '#{group_name}'..."
    body = {
      data: {
        type: "betaGroups",
        attributes: {
          name: group_name,
          isInternalGroup: false,
          publicLinkEnabled: true,
          publicLinkLimitEnabled: false
        },
        relationships: {
          app: {
            data: { type: "apps", id: app_id }
          }
        }
      }
    }

    request(:post, "/betaGroups", body: body)["data"]
  end

  # Get beta app localizations (for description)
  def get_beta_app_localizations(app_id)
    request(:get, "/apps/#{app_id}/betaAppLocalizations")
  end

  # Create or update beta app localization (description shown in TestFlight)
  def set_beta_app_description(app_id, description, locale: "en-US")
    localizations = get_beta_app_localizations(app_id)
    existing = localizations["data"]&.find { |l| l.dig("attributes", "locale") == locale }

    if existing
      # Update existing
      body = {
        data: {
          type: "betaAppLocalizations",
          id: existing["id"],
          attributes: {
            description: description
          }
        }
      }
      request(:patch, "/betaAppLocalizations/#{existing['id']}", body: body)
    else
      # Create new
      body = {
        data: {
          type: "betaAppLocalizations",
          attributes: {
            locale: locale,
            description: description
          },
          relationships: {
            app: {
              data: { type: "apps", id: app_id }
            }
          }
        }
      }
      request(:post, "/betaAppLocalizations", body: body)
    end
  end

  # Get beta build localizations (for changelog)
  def get_beta_build_localizations(build_id)
    request(:get, "/builds/#{build_id}/betaBuildLocalizations")
  end

  # Set build changelog (what's new)
  def set_build_changelog(build_id, changelog, locale: "en-US")
    localizations = get_beta_build_localizations(build_id)
    existing = localizations["data"]&.find { |l| l.dig("attributes", "locale") == locale }

    if existing
      # Update existing
      body = {
        data: {
          type: "betaBuildLocalizations",
          id: existing["id"],
          attributes: {
            whatsNew: changelog
          }
        }
      }
      request(:patch, "/betaBuildLocalizations/#{existing['id']}", body: body)
    else
      # Create new
      body = {
        data: {
          type: "betaBuildLocalizations",
          attributes: {
            locale: locale,
            whatsNew: changelog
          },
          relationships: {
            build: {
              data: { type: "builds", id: build_id }
            }
          }
        }
      }
      request(:post, "/betaBuildLocalizations", body: body)
    end
  end

  # Set beta review info (demo account, contact info)
  def set_beta_review_info(app_id, demo_name:, demo_password:, contact_email:, contact_first_name:, contact_last_name:, contact_phone:, notes:)
    # Get existing beta app review detail
    details = request(:get, "/apps/#{app_id}/betaAppReviewDetail")
    detail_id = details.dig("data", "id")

    if detail_id
      body = {
        data: {
          type: "betaAppReviewDetails",
          id: detail_id,
          attributes: {
            contactEmail: contact_email,
            contactFirstName: contact_first_name,
            contactLastName: contact_last_name,
            contactPhone: contact_phone,
            demoAccountName: demo_name,
            demoAccountPassword: demo_password,
            demoAccountRequired: true,
            notes: notes
          }
        }
      }
      request(:patch, "/betaAppReviewDetails/#{detail_id}", body: body)
    else
      raise "Could not find beta app review detail for app #{app_id}"
    end
  end

  # Add build to beta group
  def add_build_to_group(build_id, group_id)
    body = {
      data: [
        { type: "builds", id: build_id }
      ]
    }
    request(:post, "/betaGroups/#{group_id}/relationships/builds", body: body)
  end

  # Submit build for beta review
  def submit_for_beta_review(build_id)
    body = {
      data: {
        type: "betaAppReviewSubmissions",
        relationships: {
          build: {
            data: { type: "builds", id: build_id }
          }
        }
      }
    }
    request(:post, "/betaAppReviewSubmissions", body: body)
  end

  # Get beta group public link
  def get_beta_group_public_link(group_id)
    group = request(:get, "/betaGroups/#{group_id}")
    group.dig("data", "attributes", "publicLink")
  end

  private

  def request(method, path, body: nil)
    uri = URI("#{BASE_URL}#{path}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = case method
    when :get
      Net::HTTP::Get.new(uri)
    when :post
      Net::HTTP::Post.new(uri)
    when :patch
      Net::HTTP::Patch.new(uri)
    when :delete
      Net::HTTP::Delete.new(uri)
    end

    request["Authorization"] = "Bearer #{generate_token}"
    request["Content-Type"] = "application/json"

    if body
      request.body = body.to_json
    end

    response = http.request(request)

    case response.code.to_i
    when 200..299
      response.body.empty? ? {} : JSON.parse(response.body)
    when 401
      raise "Authentication failed - check API key credentials"
    when 403
      raise "Access forbidden - check API key permissions"
    when 404
      raise "Resource not found: #{path}"
    when 409
      # Conflict - often means resource already exists, which is fine
      response.body.empty? ? {} : JSON.parse(response.body)
    else
      error_msg = begin
        JSON.parse(response.body).dig("errors", 0, "detail") || response.body
      rescue
        response.body
      end
      raise "API error (#{response.code}): #{error_msg}"
    end
  end
end

# CLI interface for shell script
if __FILE__ == $0
  require 'optparse'

  options = {}
  command = ARGV.shift

  OptionParser.new do |opts|
    opts.banner = "Usage: asc_api.rb COMMAND [options]"

    opts.on("--key-id ID", "API Key ID") { |v| options[:key_id] = v }
    opts.on("--issuer-id ID", "Issuer ID") { |v| options[:issuer_id] = v }
    opts.on("--key-path PATH", "Path to .p8 key file") { |v| options[:key_path] = v }
    opts.on("--app-id ID", "App ID") { |v| options[:app_id] = v }
    opts.on("--build-id ID", "Build ID") { |v| options[:build_id] = v }
    opts.on("--group-id ID", "Beta Group ID") { |v| options[:group_id] = v }
    opts.on("--version VERSION", "Marketing version") { |v| options[:version] = v }
    opts.on("--build-number NUMBER", "Build number") { |v| options[:build_number] = v }
    opts.on("--changelog TEXT", "What's new text") { |v| options[:changelog] = v }
    opts.on("--description TEXT", "Beta app description") { |v| options[:description] = v }
    opts.on("--group-name NAME", "Beta group name") { |v| options[:group_name] = v }
    opts.on("--demo-name NAME", "Demo account name") { |v| options[:demo_name] = v }
    opts.on("--demo-password PASS", "Demo account password") { |v| options[:demo_password] = v }
    opts.on("--contact-email EMAIL", "Contact email") { |v| options[:contact_email] = v }
    opts.on("--contact-first-name NAME", "Contact first name") { |v| options[:contact_first_name] = v }
    opts.on("--contact-last-name NAME", "Contact last name") { |v| options[:contact_last_name] = v }
    opts.on("--contact-phone PHONE", "Contact phone") { |v| options[:contact_phone] = v }
    opts.on("--notes TEXT", "Review notes") { |v| options[:notes] = v }
    opts.on("--timeout SECONDS", Integer, "Timeout in seconds") { |v| options[:timeout] = v }
  end.parse!

  api = AppStoreConnectAPI.new(
    key_id: options[:key_id] || ENV['ASC_KEY_ID'],
    issuer_id: options[:issuer_id] || ENV['ASC_ISSUER_ID'],
    key_path: options[:key_path] || ENV['ASC_KEY_PATH']
  )

  result = case command
  when "get-build"
    api.get_build(options[:app_id], options[:version], options[:build_number], timeout: options[:timeout] || 600)
  when "get-or-create-group"
    api.get_or_create_beta_group(options[:app_id], options[:group_name])
  when "set-description"
    api.set_beta_app_description(options[:app_id], options[:description])
  when "set-changelog"
    api.set_build_changelog(options[:build_id], options[:changelog])
  when "set-review-info"
    api.set_beta_review_info(
      options[:app_id],
      demo_name: options[:demo_name],
      demo_password: options[:demo_password],
      contact_email: options[:contact_email],
      contact_first_name: options[:contact_first_name],
      contact_last_name: options[:contact_last_name],
      contact_phone: options[:contact_phone],
      notes: options[:notes]
    )
  when "add-to-group"
    api.add_build_to_group(options[:build_id], options[:group_id])
  when "submit-review"
    api.submit_for_beta_review(options[:build_id])
  when "get-public-link"
    api.get_beta_group_public_link(options[:group_id])
  else
    puts "Unknown command: #{command}"
    puts "Available commands: get-build, get-or-create-group, set-description, set-changelog, set-review-info, add-to-group, submit-review, get-public-link"
    exit 1
  end

  puts result.to_json
end
