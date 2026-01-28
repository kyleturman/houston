# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Web::BrowserConfig do
  let(:config) { described_class.new }

  describe '#initialize' do
    it 'selects a user agent from the pool' do
      expect(described_class::USER_AGENTS).to include(config.user_agent)
    end

    it 'extracts chrome version from user agent' do
      expect(config.chrome_version).to be_present
      expect(config.chrome_version).to match(/^\d+$/)
    end
  end

  describe '#browser_options' do
    it 'returns hash with required browser options' do
      opts = config.browser_options

      expect(opts[:headless]).to eq(true)
      expect(opts[:window_size]).to eq([1366, 768])
      expect(opts[:browser_path]).to eq('/usr/bin/chromium-browser')
      expect(opts[:browser_options]).to be_a(Hash)
    end

    it 'includes extension path if file exists' do
      extension_path = Rails.root.join('vendor', 'browser-extensions', 'stealth.min.js')

      if File.exist?(extension_path)
        opts = config.browser_options
        expect(opts[:extensions]).to include(extension_path)
      end
    end

    it 'accepts custom timeout' do
      opts = config.browser_options(timeout: 60)
      expect(opts[:timeout]).to eq(60)
    end
  end

  describe '#chrome_flags' do
    it 'returns hash with string keys (required by Ferrum)' do
      flags = config.chrome_flags
      flags.each_key do |key|
        expect(key).to be_a(String), "Expected string key, got #{key.class}: #{key}"
      end
    end

    it 'includes automation flag' do
      flags = config.chrome_flags
      expect(flags['disable-blink-features']).to eq('AutomationControlled')
    end

    it 'includes user agent' do
      flags = config.chrome_flags
      expect(flags['user-agent']).to eq(config.user_agent)
    end

    it 'includes sandbox flags' do
      flags = config.chrome_flags
      expect(flags).to have_key('no-sandbox')
      expect(flags).to have_key('disable-dev-shm-usage')
    end
  end

  describe '#headers' do
    it 'returns hash with required headers' do
      headers = config.headers

      expect(headers['Accept']).to be_present
      expect(headers['Accept-Encoding']).to eq('gzip, deflate, br, zstd')
      expect(headers['User-Agent']).to eq(config.user_agent)
      expect(headers['Sec-CH-UA']).to be_present
      expect(headers['Sec-Fetch-Dest']).to eq('document')
    end

    it 'includes client hints matching chrome version' do
      headers = config.headers
      expect(headers['Sec-CH-UA']).to include(config.chrome_version)
    end

    it 'includes platform hint based on user agent' do
      headers = config.headers
      platform = headers['Sec-CH-UA-Platform']

      expect(['"macOS"', '"Windows"', '"Linux"', '"Unknown"']).to include(platform)
    end
  end

  describe '#should_block_url?' do
    it 'blocks image files' do
      expect(config.should_block_url?('https://example.com/image.jpg')).to eq(true)
      expect(config.should_block_url?('https://example.com/photo.png')).to eq(true)
      expect(config.should_block_url?('https://example.com/graphic.webp')).to eq(true)
    end

    it 'blocks video files' do
      expect(config.should_block_url?('https://example.com/video.mp4')).to eq(true)
      expect(config.should_block_url?('https://example.com/clip.webm')).to eq(true)
    end

    it 'blocks audio files' do
      expect(config.should_block_url?('https://example.com/song.mp3')).to eq(true)
      expect(config.should_block_url?('https://example.com/audio.ogg')).to eq(true)
    end

    it 'blocks font files' do
      expect(config.should_block_url?('https://example.com/font.woff')).to eq(true)
      expect(config.should_block_url?('https://example.com/font.woff2')).to eq(true)
    end

    it 'allows HTML and other resources' do
      expect(config.should_block_url?('https://example.com/page.html')).to eq(false)
      expect(config.should_block_url?('https://example.com/api/data')).to eq(false)
      expect(config.should_block_url?('https://example.com/')).to eq(false)
    end

    it 'handles nil gracefully' do
      expect(config.should_block_url?(nil)).to eq(false)
    end
  end

  describe '#proxy_options' do
    context 'in production with proxy configured' do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
        ENV['PROXY_HOST'] = 'proxy.example.com'
        ENV['PROXY_PORT'] = '8080'
        ENV['PROXY_USER'] = 'user'
        ENV['PROXY_PASSWORD'] = 'pass'
      end

      after do
        ENV.delete('PROXY_HOST')
        ENV.delete('PROXY_PORT')
        ENV.delete('PROXY_USER')
        ENV.delete('PROXY_PASSWORD')
      end

      it 'returns proxy configuration' do
        opts = config.proxy_options
        expect(opts[:host]).to eq('proxy.example.com')
        expect(opts[:port]).to eq(8080)
        expect(opts[:user]).to eq('user')
        expect(opts[:password]).to eq('pass')
      end
    end

    context 'in development' do
      it 'returns nil' do
        expect(config.proxy_options).to be_nil
      end
    end

    context 'in production without proxy configured' do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it 'returns nil' do
        expect(config.proxy_options).to be_nil
      end
    end
  end
end
