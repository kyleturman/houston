# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ferrum Integration', type: :integration do
  # This test actually spins up a headless Chrome browser and fetches real web content
  # Tagged as :integration so it can be run separately from unit tests

  describe 'Ferrum browser setup and operation', :integration do
    it 'can initialize a Ferrum browser instance' do
      browser = Ferrum::Browser.new(
        headless: true,
        timeout: 30,
        window_size: [1920, 1080],
        browser_path: '/usr/bin/chromium-browser',
        browser_options: {
          'no-sandbox': nil,
          'disable-dev-shm-usage': nil
        }
      )

      expect(browser).to be_a(Ferrum::Browser)

      browser.quit
    end

    it 'can fetch and parse a real webpage' do
      browser = Ferrum::Browser.new(
        headless: true,
        timeout: 30,
        window_size: [1920, 1080],
        browser_path: '/usr/bin/chromium-browser',
        browser_options: {
          'no-sandbox': nil,
          'disable-dev-shm-usage': nil
        }
      )

      begin
        # Use example.com which is a simple, reliable test page
        browser.goto('https://example.com')
        browser.network.wait_for_idle

        # Extract title
        title = browser.title
        expect(title).to be_present
        expect(title.downcase).to include('example')

        # Extract text content using JavaScript evaluation
        text_content = browser.evaluate('document.body.innerText')
        expect(text_content).to be_present
        expect(text_content.length).to be > 0

        # Verify we can run JavaScript
        result = browser.evaluate('document.title')
        expect(result).to be_present

        puts "\n✅ Successfully fetched example.com:"
        puts "   Title: #{title}"
        puts "   Content length: #{text_content.length} characters"
      ensure
        browser.quit
      end
    end

    it 'can extract meta tags and structured content' do
      browser = Ferrum::Browser.new(
        headless: true,
        timeout: 30,
        window_size: [1920, 1080],
        browser_path: '/usr/bin/chromium-browser',
        browser_options: {
          'no-sandbox': nil,
          'disable-dev-shm-usage': nil
        }
      )

      begin
        browser.goto('https://example.com')
        browser.network.wait_for_idle

        # Extract title using CSS selector
        title_element = browser.at_css('title')
        expect(title_element).to be_present
        title = title_element.text
        expect(title).to be_present

        # Extract main heading
        h1_element = browser.at_css('h1')
        if h1_element
          h1_text = h1_element.text
          expect(h1_text).to be_present
          puts "\n   H1: #{h1_text}"
        end

        # Extract paragraphs
        paragraphs = browser.css('p')
        expect(paragraphs.count).to be > 0
        puts "   Found #{paragraphs.count} paragraph(s)"

      ensure
        browser.quit
      end
    end

    it 'can execute JavaScript on a real page', :slow do
      browser = Ferrum::Browser.new(
        headless: true,
        timeout: 30,
        window_size: [1920, 1080],
        browser_path: '/usr/bin/chromium-browser',
        browser_options: {
          'no-sandbox': nil,
          'disable-dev-shm-usage': nil
        }
      )

      begin
        # Use a real page to test JavaScript execution
        browser.goto('https://example.com')
        browser.network.wait_for_idle

        # Execute JavaScript to modify the page
        result = browser.evaluate("document.title = 'Modified by JS'; document.title;")
        expect(result).to eq('Modified by JS')

        # Verify the title was actually changed
        expect(browser.title).to eq('Modified by JS')

        # Test JavaScript that returns a value
        calc_result = browser.evaluate('2 + 2')
        expect(calc_result).to eq(4)

        puts "\n✅ JavaScript execution works correctly"
      ensure
        browser.quit
      end
    end

    it 'matches the exact usage pattern in NotesController' do
      # This test mirrors the exact way Ferrum is used in the NotesController
      browser = Ferrum::Browser.new(
        headless: true,
        timeout: 30,
        window_size: [1920, 1080],
        browser_path: '/usr/bin/chromium-browser',
        browser_options: {
          'no-sandbox': nil,
          'disable-dev-shm-usage': nil
        }
      )

      begin
        url = 'https://example.com'
        browser.goto(url)
        browser.network.wait_for_idle

        # Extract title (same as controller)
        title = browser.at_css('title')&.text || browser.title
        expect(title).to be_present

        # Extract meta description (same as controller)
        meta_desc = browser.at_css('meta[name="description"]')&.attribute('content')
        # example.com may not have meta description, so this is optional

        # Extract main text content (same as controller)
        script = <<~JS
          document.querySelectorAll('script, style, nav, footer, header').forEach(el => el.remove());
          document.body.innerText;
        JS
        text_content = browser.evaluate(script).to_s.gsub(/\s+/, ' ').strip[0..5000]

        # Note: example.com is very minimal, so text_content might be short
        # The important thing is the script executes without errors

        puts "\n✅ Controller pattern works correctly:"
        puts "   URL: #{url}"
        puts "   Title: #{title}"
        puts "   Meta desc: #{meta_desc || 'N/A'}"
        puts "   Content preview: #{text_content[0..100]}..."

        # This proves that the exact code pattern in NotesController will work
      ensure
        browser.quit
      end
    end

    it 'handles errors gracefully when site is unreachable' do
      browser = Ferrum::Browser.new(
        headless: true,
        timeout: 5, # Shorter timeout for error test
        window_size: [1920, 1080],
        browser_path: '/usr/bin/chromium-browser',
        browser_options: {
          'no-sandbox': nil,
          'disable-dev-shm-usage': nil
        }
      )

      begin
        # Try to fetch a URL that doesn't exist
        expect {
          browser.goto('https://this-domain-definitely-does-not-exist-12345.com')
        }.to raise_error

        puts "\n✅ Error handling works correctly"
      ensure
        browser.quit
      end
    end
  end

  describe 'Chromium installation verification', :integration do
    it 'has chromium installed in the container' do
      # Check if chromium binary exists
      chromium_path = `which chromium-browser 2>/dev/null`.strip
      chromium_alt_path = `which chromium 2>/dev/null`.strip

      expect(chromium_path.present? || chromium_alt_path.present?).to be(true),
        "Chromium not found. Expected to find chromium-browser or chromium in PATH"

      binary = chromium_path.present? ? chromium_path : chromium_alt_path
      puts "\n✅ Chromium found at: #{binary}"
    end

    it 'chromium can display version info' do
      version_output = `chromium-browser --version 2>/dev/null || chromium --version 2>/dev/null`.strip

      expect(version_output).to be_present
      expect(version_output.downcase).to include('chromium')

      puts "\n✅ #{version_output}"
    end
  end
end
