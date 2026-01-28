# frozen_string_literal: true

module Web
  class BrowserConfig
    # User agents pool for rotation
    USER_AGENTS = [
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    ].freeze

    # Resource types to block for bandwidth optimization
    BLOCKED_RESOURCE_TYPES = %w[
      image media font stylesheet
    ].freeze

    # File extensions to block
    BLOCKED_EXTENSIONS = %w[
      .jpg .jpeg .png .gif .bmp .svg .webp .avif
      .mp4 .avi .mov .mkv .webm
      .mp3 .ogg .wav .aac .flac
      .woff .woff2 .ttf .otf .eot
    ].freeze

    attr_reader :user_agent, :chrome_version

    def initialize
      @user_agent = USER_AGENTS.sample
      @chrome_version = extract_chrome_version(@user_agent)
    end

    # Browser initialization options
    def browser_options(timeout: 30)
      opts = {
        headless: true,
        timeout: timeout,
        window_size: [1366, 768], # Standard viewport size
        browser_options: chrome_flags
      }

      # Set browser path based on platform
      browser_path = detect_browser_path
      opts[:browser_path] = browser_path if browser_path

      # Add browser extension if available
      extension_path = Rails.root.join('vendor', 'browser-extensions', 'stealth.min.js')
      if File.exist?(extension_path)
        opts[:extensions] = [extension_path]
      end

      opts
    end

    # Chrome command-line flags
    def chrome_flags
      {
        'no-sandbox' => nil,
        'disable-dev-shm-usage' => nil,
        'disable-blink-features' => 'AutomationControlled', # Improves compatibility
        'user-agent' => @user_agent
      }
    end

    # HTTP headers for requests
    def headers
      {
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Encoding' => 'gzip, deflate, br, zstd',
        'Accept-Language' => 'en-US,en;q=0.9',
        'Sec-CH-UA' => client_hints,
        'Sec-CH-UA-Mobile' => '?0',
        'Sec-CH-UA-Platform' => platform_from_user_agent,
        'Sec-Fetch-Dest' => 'document',
        'Sec-Fetch-Mode' => 'navigate',
        'Sec-Fetch-Site' => 'none',
        'Sec-Fetch-User' => '?1',
        'Upgrade-Insecure-Requests' => '1',
        'User-Agent' => @user_agent
      }
    end

    # Check if URL should be blocked for optimization
    def should_block_url?(url)
      return false unless url.is_a?(String)

      # Check file extension
      BLOCKED_EXTENSIONS.any? { |ext| url.downcase.include?(ext) }
    end

    # Proxy configuration (production only)
    def proxy_options
      return nil unless Rails.env.production? && ENV['PROXY_HOST'].present?

      {
        host: ENV['PROXY_HOST'],
        port: ENV['PROXY_PORT']&.to_i || 8080,
        user: ENV['PROXY_USER'],
        password: ENV['PROXY_PASSWORD']
      }.compact
    end

    private

    def detect_browser_path
      # Check common browser locations based on platform
      paths = if RUBY_PLATFORM.match?(/darwin/)
                # macOS
                [
                  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
                  '/Applications/Chromium.app/Contents/MacOS/Chromium'
                ]
              elsif RUBY_PLATFORM.match?(/linux/)
                # Linux
                [
                  '/usr/bin/chromium-browser',
                  '/usr/bin/chromium',
                  '/usr/bin/google-chrome',
                  '/usr/bin/google-chrome-stable'
                ]
              else
                # Windows or other
                []
              end

      paths.find { |path| File.exist?(path) }
    end

    def extract_chrome_version(ua)
      match = ua.match(/Chrome\/(\d+)\./)
      match ? match[1] : '131'
    end

    def client_hints
      "\"Chromium\";v=\"#{@chrome_version}\", \"Not(A:Brand\";v=\"24\", \"Google Chrome\";v=\"#{@chrome_version}\""
    end

    def platform_from_user_agent
      case @user_agent
      when /Mac OS X/ then '"macOS"'
      when /Windows/ then '"Windows"'
      when /Linux/ then '"Linux"'
      else '"Unknown"'
      end
    end
  end
end
