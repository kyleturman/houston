# frozen_string_literal: true

module Web
  # Lightweight OG metadata fetcher using simple HTTP requests
  # Much faster than full browser rendering for just extracting meta tags
  class OgMetadataFetcher
    TIMEOUT = 10 # seconds
    MAX_BODY_SIZE = 100_000 # 100KB - we only need the <head> section

    # Fetch OG image URL from a webpage
    # @param url [String] URL to fetch
    # @return [String, nil] OG image URL or nil if not found
    def self.fetch_og_image(url)
      # YouTube has predictable thumbnail URLs - no need to fetch HTML
      if youtube_url?(url)
        return youtube_thumbnail(url)
      end

      html = fetch_html(url)
      return nil unless html

      extract_og_image(html)
    rescue => e
      Rails.logger.warn("[OgMetadataFetcher] Failed to fetch OG image for #{url}: #{e.message}")
      nil
    end

    # Check if URL is a YouTube video
    def self.youtube_url?(url)
      url.match?(/(?:youtube\.com\/watch|youtu\.be\/)/)
    end

    # Extract YouTube video ID and construct thumbnail URL
    # YouTube thumbnails are available at predictable URLs:
    # - maxresdefault.jpg (1280x720, may not exist for all videos)
    # - hqdefault.jpg (480x360, always exists)
    def self.youtube_thumbnail(url)
      video_id = extract_youtube_video_id(url)
      return nil unless video_id

      # Use hqdefault as it's guaranteed to exist
      "https://img.youtube.com/vi/#{video_id}/hqdefault.jpg"
    end

    # Extract video ID from YouTube URL
    def self.extract_youtube_video_id(url)
      # Match youtube.com/watch?v=VIDEO_ID or youtu.be/VIDEO_ID
      match = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/)
      match ? match[1] : nil
    end

    # Fetch basic OG metadata (title, description, image)
    # @param url [String] URL to fetch
    # @return [Hash] { title:, description:, image:, site_name: }
    def self.fetch_metadata(url)
      html = fetch_html(url)
      return {} unless html

      {
        title: extract_meta_content(html, 'og:title') || extract_title(html),
        description: extract_meta_content(html, 'og:description'),
        image: extract_og_image(html),
        site_name: extract_meta_content(html, 'og:site_name')
      }.compact
    rescue => e
      Rails.logger.warn("[OgMetadataFetcher] Failed to fetch metadata for #{url}: #{e.message}")
      {}
    end

    private

    def self.fetch_html(url)
      uri = URI.parse(url)

      # Follow redirects (up to 3)
      response = nil
      3.times do
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT

        request = Net::HTTP::Get.new(uri.request_uri)
        request['User-Agent'] = 'Mozilla/5.0 (compatible; HoustonBot/1.0)'
        request['Accept'] = 'text/html'

        response = http.request(request)

        # Handle redirects
        if response.is_a?(Net::HTTPRedirection)
          redirect_url = response['location']
          # Handle relative redirects
          uri = redirect_url.start_with?('http') ? URI.parse(redirect_url) : URI.join(uri, redirect_url)
          next
        end

        break
      end

      return nil unless response.is_a?(Net::HTTPSuccess)

      # Get body, limiting size
      body = response.body
      body = body[0...MAX_BODY_SIZE] if body.length > MAX_BODY_SIZE

      # Ensure UTF-8 encoding
      body.force_encoding('UTF-8')
      body = body.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')

      body
    rescue Net::TimeoutError, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
      Rails.logger.debug("[OgMetadataFetcher] Network error for #{url}: #{e.message}")
      nil
    end

    def self.extract_og_image(html)
      # Try og:image first
      image = extract_meta_content(html, 'og:image')
      return image if image.present?

      # Fall back to twitter:image
      extract_meta_content(html, 'twitter:image', name_attr: 'name')
    end

    def self.extract_meta_content(html, property, name_attr: 'property')
      # Match: <meta property="og:image" content="...">
      # or: <meta name="twitter:image" content="...">
      pattern = /<meta[^>]+#{name_attr}=["']#{Regexp.escape(property)}["'][^>]+content=["']([^"']+)["']/i
      match = html.match(pattern)
      return match[1] if match

      # Try alternate order: content before property
      pattern = /<meta[^>]+content=["']([^"']+)["'][^>]+#{name_attr}=["']#{Regexp.escape(property)}["']/i
      match = html.match(pattern)
      match ? match[1] : nil
    end

    def self.extract_title(html)
      match = html.match(/<title[^>]*>([^<]+)<\/title>/i)
      match ? match[1].strip : nil
    end
  end
end
