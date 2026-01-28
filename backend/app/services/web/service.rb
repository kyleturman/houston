# frozen_string_literal: true

module Web
  class Service
    class FetchError < StandardError; end

    # Fetch web content with all metadata and images
    #
    # @param url [String] URL to fetch
    # @param clean [Boolean] Clean HTML from content (default: true)
    # @param metadata [Boolean] Extract SEO/OG metadata (default: true)
    # @param images [Boolean] Extract and filter images (default: true)
    # @return [Hash] { url:, title:, content:, metadata:, images:, fetched_at: }
    def self.fetch(url, clean: true, metadata: true, images: true)
      # Disable resource blocking when extracting images
      browser = initialize_browser(block_resources: !images)

      begin
        # Navigate to URL
        browser.goto(url)
        browser.network.wait_for_idle

        result = {
          url: url,
          fetched_at: Time.current
        }

        # Extract metadata if requested
        if metadata
          meta_data = extract_metadata(browser)
          result[:title] = meta_data[:title]
          result[:metadata] = meta_data
        else
          # At minimum, get the title
          result[:title] = browser.title
        end

        # Check for structured data FIRST (before cleaning removes scripts)
        structured_data = extract_structured_data(browser)

        # Extract video transcript if this is a video platform
        transcript = extract_video_transcript(browser, url)

        # Extract content (this may remove scripts from DOM if clean=true)
        content_data = extract_content(browser, clean: clean)

        # Build content with structured data and transcript
        content_parts = []
        content_parts << "STRUCTURED DATA:\n#{structured_data.to_json}" if structured_data
        content_parts << "TRANSCRIPT:\n#{transcript}" if transcript.present?
        content_parts << "PAGE CONTENT:\n#{content_data[:text]}"

        result[:content] = content_parts.join("\n\n")
        result[:content_structure] = content_data[:structure]
        result[:content_structure][:structured_data_type] = structured_data[:@type] if structured_data
        result[:content_structure][:has_transcript] = transcript.present?

        # Extract images if requested
        result[:images] = images ? extract_images(browser) : []

        result
      ensure
        browser.quit if browser
      end
    rescue => e
      Rails.logger.error("[Web::Service] Fetch error for #{url}: #{e.message}")
      raise FetchError, "Failed to fetch #{url}: #{e.message}"
    end

    # Extract only metadata (SEO, OG, Twitter, favicon)
    def self.fetch_metadata(url)
      browser = initialize_browser

      begin
        browser.goto(url)
        browser.network.wait_for_idle
        extract_metadata(browser)
      ensure
        browser.quit if browser
      end
    rescue => e
      Rails.logger.error("[Web::Service] Metadata fetch error for #{url}: #{e.message}")
      raise FetchError, "Failed to fetch metadata from #{url}: #{e.message}"
    end

    # Extract only content (optionally cleaned)
    def self.fetch_content(url, clean: false)
      browser = initialize_browser

      begin
        browser.goto(url)
        browser.network.wait_for_idle
        extract_content(browser, clean: clean)
      ensure
        browser.quit if browser
      end
    rescue => e
      Rails.logger.error("[Web::Service] Content fetch error for #{url}: #{e.message}")
      raise FetchError, "Failed to fetch content from #{url}: #{e.message}"
    end

    # Extract only images
    def self.fetch_images(url)
      browser = initialize_browser

      begin
        browser.goto(url)
        browser.network.wait_for_idle
        extract_images(browser)
      ensure
        browser.quit if browser
      end
    rescue => e
      Rails.logger.error("[Web::Service] Images fetch error for #{url}: #{e.message}")
      raise FetchError, "Failed to fetch images from #{url}: #{e.message}"
    end

    private_class_method def self.initialize_browser(timeout: 30, block_resources: true)
      config = BrowserConfig.new
      options = config.browser_options(timeout: timeout)

      # Add proxy if configured
      options[:proxy] = config.proxy_options if config.proxy_options

      browser = Ferrum::Browser.new(options)

      # Custom headers disabled - they trigger bot detection on some sites like NYT
      # The browser's default headers work better for content extraction
      # browser.headers.set(config.headers)

      # Enable resource blocking for optimization
      if block_resources
        setup_resource_blocking(browser, config)
      end

      browser
    end

    # Configure resource blocking to optimize bandwidth and speed
    private_class_method def self.setup_resource_blocking(browser, config)
      browser.network.intercept

      browser.on(:request) do |request|
        if config.should_block_url?(request.url)
          request.abort
        else
          request.continue
        end
      end
    rescue => e
      # Don't fail browser initialization if interception setup fails
      Rails.logger.warn("[Web::Service] Resource blocking setup failed: #{e.message}")
    end

    # Extract comprehensive metadata (SEO, Open Graph, Twitter, favicon)
    private_class_method def self.extract_metadata(browser)
      script = <<~JS
        (function() {
          function getContent(selector, attr) {
            var el = document.querySelector(selector);
            if (!el) return null;
            return attr ? el[attr] : el.innerText;
          }

          var titleEl = document.querySelector('title');
          var metadata = {
            title: titleEl ? titleEl.innerText : document.title,
            description: getContent('meta[name="description"]', 'content'),
            keywords: getContent('meta[name="keywords"]', 'content'),
            author: getContent('meta[name="author"]', 'content'),
            canonical: getContent('link[rel="canonical"]', 'href'),
            og_title: getContent('meta[property="og:title"]', 'content'),
            og_description: getContent('meta[property="og:description"]', 'content'),
            og_image: getContent('meta[property="og:image"]', 'content'),
            og_url: getContent('meta[property="og:url"]', 'content'),
            og_type: getContent('meta[property="og:type"]', 'content'),
            og_site_name: getContent('meta[property="og:site_name"]', 'content'),
            twitter_card: getContent('meta[name="twitter:card"]', 'content'),
            twitter_title: getContent('meta[name="twitter:title"]', 'content'),
            twitter_description: getContent('meta[name="twitter:description"]', 'content'),
            twitter_image: getContent('meta[name="twitter:image"]', 'content'),
            favicon: getContent('link[rel*="icon"]', 'href') || '/favicon.ico'
          };

          return JSON.stringify(metadata);
        })();
      JS

      raw_metadata = browser.evaluate(script)
      parsed = JSON.parse(raw_metadata)

      # Organize into structured sections
      {
        title: parsed['title'],
        seo: {
          title: parsed['title'],
          description: parsed['description'],
          keywords: parsed['keywords'],
          author: parsed['author'],
          canonical_url: parsed['canonical']
        }.compact,
        og: {
          title: parsed['og_title'],
          description: parsed['og_description'],
          image: parsed['og_image'],
          url: parsed['og_url'],
          type: parsed['og_type'],
          site_name: parsed['og_site_name']
        }.compact,
        twitter: {
          card: parsed['twitter_card'],
          title: parsed['twitter_title'],
          description: parsed['twitter_description'],
          image: parsed['twitter_image']
        }.compact,
        assets: {
          favicon: parsed['favicon']
        }.compact
      }
    end

    # Extract and optionally clean page content
    private_class_method def self.extract_content(browser, clean: false)
      if clean
        # Remove noise and extract clean content
        script = <<~JS
          (function() {
            // Remove noise elements
            var noiseSelectors = 'script, style, nav, footer, header, aside, iframe, noscript, .ad, .advertisement, .social-share, [role="navigation"], [role="complementary"], [role="banner"]';
            var noiseElements = document.querySelectorAll(noiseSelectors);
            for (var i = 0; i < noiseElements.length; i++) {
              noiseElements[i].remove();
            }

            // Find main content
            var main = document.querySelector('main') ||
                       document.querySelector('article') ||
                       document.querySelector('[role="main"]') ||
                       document.body;

            // Extract headings
            var headingElements = main.querySelectorAll('h1, h2, h3');
            var headings = [];
            for (var i = 0; i < Math.min(headingElements.length, 10); i++) {
              var h = headingElements[i];
              headings.push({
                level: h.tagName.toLowerCase(),
                text: h.innerText.trim()
              });
            }

            // Extract with structure
            var result = {
              text: main.innerText.replace(/\\s+/g, ' ').trim().substring(0, 10000),
              headings: headings
            };

            return JSON.stringify(result);
          })();
        JS

        content_json = browser.evaluate(script)
        parsed = JSON.parse(content_json)

        {
          text: parsed['text'],
          structure: {
            headings: parsed['headings']
          }
        }
      else
        # Return raw content (browser.body returns HTML string, we need text)
        script = 'document.body.innerText'
        text = browser.evaluate(script).gsub(/\s+/, ' ').strip[0..10000]
        { text: text, structure: {} }
      end
    end

    # Extract and filter images (remove ads, tracking pixels, icons)
    private_class_method def self.extract_images(browser)
      script = <<~JS
        (function() {
          var imgElements = document.querySelectorAll('img');
          var images = [];

          for (var i = 0; i < imgElements.length; i++) {
            var img = imgElements[i];
            var width = img.naturalWidth || parseInt(img.getAttribute('width'), 10) || 0;
            var height = img.naturalHeight || parseInt(img.getAttribute('height'), 10) || 0;
            var className = img.className || '';

            // Check if image is in main content
            var inMain = false;
            var parent = img;
            while (parent && parent !== document.body) {
              var tag = parent.tagName ? parent.tagName.toLowerCase() : '';
              var role = parent.getAttribute ? parent.getAttribute('role') : '';
              if (tag === 'article' || tag === 'main' || role === 'main' ||
                  className.indexOf('content') >= 0 || className.indexOf('post') >= 0 ||
                  className.indexOf('entry') >= 0) {
                inMain = true;
                break;
              }
              parent = parent.parentElement;
            }

            images.push({
              url: img.src,
              alt: img.alt || '',
              width: width,
              height: height,
              className: className,
              inMain: inMain
            });
          }

          // Filter images
          var filtered = [];
          var badClasses = ['ad', 'banner', 'logo', 'icon', 'avatar', 'social', 'badge', 'button'];

          for (var i = 0; i < images.length && filtered.length < 10; i++) {
            var img = images[i];

            // Filter out tiny images
            if (img.width < 100 || img.height < 100) continue;
            if (img.width === 1 || img.height === 1) continue;

            // Filter out bad class names
            var lowerClass = img.className.toLowerCase();
            var hasBadClass = false;
            for (var j = 0; j < badClasses.length; j++) {
              if (lowerClass.indexOf(badClasses[j]) >= 0) {
                hasBadClass = true;
                break;
              }
            }
            if (hasBadClass) continue;

            // Prefer images in main content
            if (!img.inMain) continue;

            filtered.push({
              url: img.url,
              alt: img.alt
            });
          }

          return JSON.stringify(filtered);
        })();
      JS

      images_json = browser.evaluate(script)
      JSON.parse(images_json).map(&:with_indifferent_access)
    rescue => e
      Rails.logger.error("[Web::Service] Image extraction error: #{e.message}")
      []
    end

    # Extract JSON-LD structured data (Recipe, Article, Product, etc.)
    private_class_method def self.extract_structured_data(browser)
      # Get raw HTML and parse in Ruby (more reliable than JS evaluation)
      html = browser.body
      relevant_types = [
        'Recipe', 'Article', 'NewsArticle', 'BlogPosting', 'Product', 'HowTo', 'Course',
        'VideoObject', 'Movie', 'Book', 'Event', 'LocalBusiness', 'Restaurant',
        'ScholarlyArticle', 'ResearchArticle'
      ]

      # Find all script tags with type="application/ld+json"
      matches = html.scan(/<script[^>]*type=["']application\/ld\+json["'][^>]*>(.*?)<\/script>/m)

      matches.each do |match|
        script_content = match[0]
        next if script_content.strip.empty?

        begin
          data = JSON.parse(script_content).with_indifferent_access

          # Handle arrays of structured data
          if data.is_a?(Array)
            data.each do |item|
              if item[:@type] && relevant_types.include?(item[:@type])
                Rails.logger.info("[Web::Service] Found structured data type: #{item[:@type]}")
                return item
              end
            end
          end

          # Handle single object
          if data[:@type] && relevant_types.include?(data[:@type])
            Rails.logger.info("[Web::Service] Found structured data type: #{data[:@type]}")
            return data
          end
        rescue JSON::ParserError => e
          Rails.logger.debug("[Web::Service] Skipping invalid JSON-LD: #{e.message}")
          next
        end
      end

      Rails.logger.debug("[Web::Service] No relevant structured data found")
      nil
    rescue => e
      Rails.logger.warn("[Web::Service] Structured data extraction error: #{e.message}")
      nil
    end

    # Extract video transcript from supported platforms
    private_class_method def self.extract_video_transcript(browser, url)
      return nil unless video_platform?(url)

      if youtube_url?(url)
        extract_youtube_transcript(browser, url)
      else
        nil
      end
    rescue => e
      Rails.logger.warn("[Web::Service] Video transcript extraction error: #{e.message}")
      nil
    end

    # Check if URL is a video platform
    private_class_method def self.video_platform?(url)
      youtube_url?(url)
      # Add more platforms later: vimeo_url?(url) || dailymotion_url?(url)
    end

    # Check if URL is YouTube
    private_class_method def self.youtube_url?(url)
      url.match?(/(?:youtube\.com|youtu\.be)/)
    end

    # Extract YouTube transcript using Python youtube-transcript-api library
    private_class_method def self.extract_youtube_transcript(browser, url)
      require 'json'
      require 'open3'

      # Extract video ID from URL
      video_id = extract_youtube_video_id(url)
      return nil if video_id.blank?

      # Path to Python script
      script_path = Rails.root.join('lib', 'youtube_transcript_fetcher.py')

      unless File.exist?(script_path)
        Rails.logger.warn("[Web::Service] YouTube transcript fetcher script not found")
        return nil
      end

      Rails.logger.info("[Web::Service] Fetching YouTube transcript for video: #{video_id}")

      # Use venv Python if available, fallback to system python3
      python_path = Rails.root.join('venv', 'bin', 'python3')
      python_cmd = File.exist?(python_path) ? python_path.to_s : 'python3'

      # Call Python script with video ID
      stdout, stderr, status = Open3.capture3(python_cmd, script_path.to_s, video_id)

      unless status.success?
        Rails.logger.warn("[Web::Service] Python script failed: #{stderr}")
        return nil
      end

      # Parse JSON response
      result = JSON.parse(stdout)

      if result['success']
        transcript = result['transcript']
        language = result['language']

        Rails.logger.info("[Web::Service] Successfully extracted transcript: #{transcript.length} chars (#{language})")
        transcript
      else
        Rails.logger.debug("[Web::Service] Transcript extraction failed: #{result['error']}")
        nil
      end
    rescue JSON::ParserError => e
      Rails.logger.warn("[Web::Service] Failed to parse transcript response: #{e.message}")
      nil
    rescue => e
      Rails.logger.warn("[Web::Service] YouTube transcript extraction failed: #{e.class}: #{e.message}")
      Rails.logger.debug(e.backtrace.first(5).join("\n"))
      nil
    end

    # Extract video ID from YouTube URL
    private_class_method def self.extract_youtube_video_id(url)
      # Match youtube.com/watch?v=VIDEO_ID or youtu.be/VIDEO_ID
      match = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/)
      match ? match[1] : nil
    end

    # Parse YouTube transcript (supports XML and JSON3 formats)
    private_class_method def self.parse_youtube_transcript(raw_data, format: :xml)
      require 'cgi'
      return nil if raw_data.blank?

      transcript = if format == :json3
                     parse_json3_transcript(raw_data)
                   else
                     parse_xml_transcript(raw_data)
                   end

      if transcript.present?
        Rails.logger.info("[Web::Service] Extracted transcript: #{transcript.length} chars")
        transcript
      else
        nil
      end
    rescue => e
      Rails.logger.warn("[Web::Service] YouTube transcript parsing failed: #{e.message}")
      nil
    end

    # Parse JSON3 format transcript
    private_class_method def self.parse_json3_transcript(raw_data)
      data = JSON.parse(raw_data)
      return nil unless data['events']

      # Extract text from events that have segments
      texts = data['events']
        .select { |event| event['segs'] }
        .flat_map { |event| event['segs'] }
        .map { |seg| seg['utf8'] }
        .compact

      if texts.any?
        texts
          .map { |t| t.gsub(/[\u200B-\u200D\uFEFF]/, '') } # Remove zero-width chars
          .map { |t| t.gsub(/\s+/, ' ').strip }
          .reject(&:blank?)
          .join(' ')
      else
        nil
      end
    end

    # Parse XML format transcript
    private_class_method def self.parse_xml_transcript(raw_data)
      # Extract all text content from <text> tags
      texts = raw_data.scan(/<text[^>]*>(.*?)<\/text>/m).flatten

      if texts.any?
        texts
          .map { |t| CGI.unescapeHTML(t) }
          .map { |t| t.gsub(/\n/, ' ').strip }
          .reject(&:blank?)
          .join(' ')
      else
        nil
      end
    end
  end
end
