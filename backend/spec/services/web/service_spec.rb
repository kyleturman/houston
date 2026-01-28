# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Web::Service do
  describe '.fetch', :slow do
    let(:test_url) { 'https://example.com' }

    context 'browser initialization' do
      it 'calls headers.set with a Hash (not key, value)' do
        # This test would have caught the "wrong number of arguments" bug
        browser_spy = nil
        headers_called_with = nil

        # Spy on Ferrum::Browser.new to capture initialization
        allow(Ferrum::Browser).to receive(:new) do |options|
          browser_spy = double('Ferrum::Browser')

          # Verify browser options use string keys
          expect(options[:browser_options]).to be_a(Hash)
          options[:browser_options].each_key do |key|
            expect(key).to be_a(String), "Chrome flags must use string keys, got: #{key.class}"
          end

          # THIS IS THE CRITICAL TEST - headers.set must be called with a Hash
          headers_spy = double('Headers')
          allow(headers_spy).to receive(:set) do |arg|
            headers_called_with = arg
          end
          allow(browser_spy).to receive(:headers).and_return(headers_spy)

          # Mock all other browser methods to prevent actual browser calls
          allow(browser_spy).to receive(:goto)
          allow(browser_spy).to receive_message_chain(:network, :wait_for_idle)
          allow(browser_spy).to receive_message_chain(:network, :intercept)
          allow(browser_spy).to receive(:on)
          allow(browser_spy).to receive(:title).and_return('Test Page')
          allow(browser_spy).to receive(:evaluate).and_return(
            '{"title":"Test","description":null,"og_title":null,"og_description":null,"og_image":null,"og_url":null,"og_type":null,"og_site_name":null,"twitter_card":null,"twitter_title":null,"twitter_description":null,"twitter_image":null,"favicon":"/favicon.ico","keywords":null,"author":null,"canonical":null}'
          )
          allow(browser_spy).to receive_message_chain(:body, :text).and_return('Sample content')
          allow(browser_spy).to receive(:quit)

          browser_spy
        end

        # Mock Llms::Service to avoid actual LLM calls
        allow(Llms::Service).to receive(:summarize).and_return('Test summary')

        # Execute - this should work without "wrong number of arguments" error
        result = described_class.fetch(test_url, clean: true, metadata: true, images: false)

        expect(result[:url]).to eq(test_url)
        expect(result[:title]).to eq('Test')
        expect(browser_spy).to have_received(:quit)

        # Verify headers.set was called with a Hash (would fail if called with key, value)
        expect(headers_called_with).to be_a(Hash)
        expect(headers_called_with.keys.first).to be_a(String)
      end
    end

    context 'error handling' do
      it 'raises FetchError when browser initialization fails' do
        allow(Ferrum::Browser).to receive(:new).and_raise(StandardError.new('Browser failed'))

        expect {
          described_class.fetch(test_url)
        }.to raise_error(Web::Service::FetchError, /Failed to fetch/)
      end

      it 'raises FetchError and closes browser when navigation fails' do
        browser_spy = double('Ferrum::Browser')
        allow(Ferrum::Browser).to receive(:new).and_return(browser_spy)
        allow(browser_spy).to receive_message_chain(:headers, :set)
        allow(browser_spy).to receive_message_chain(:network, :intercept)
        allow(browser_spy).to receive(:on)
        allow(browser_spy).to receive(:goto).and_raise(StandardError.new('Navigation failed'))
        allow(browser_spy).to receive(:quit)

        expect {
          described_class.fetch(test_url)
        }.to raise_error(Web::Service::FetchError, /Failed to fetch/)

        expect(browser_spy).to have_received(:quit)
      end
    end
  end

  describe '.fetch_metadata', :slow do
    it 'only fetches metadata without content summarization' do
      browser_spy = double('Ferrum::Browser')
      allow(Ferrum::Browser).to receive(:new).and_return(browser_spy)

      allow(browser_spy).to receive_message_chain(:headers, :set)
      allow(browser_spy).to receive_message_chain(:network, :intercept)
      allow(browser_spy).to receive(:on)
      allow(browser_spy).to receive(:goto)
      allow(browser_spy).to receive_message_chain(:network, :wait_for_idle)
      allow(browser_spy).to receive(:evaluate).and_return('{"title":"Test"}')
      allow(browser_spy).to receive(:quit)

      # Should not call LLM summarization
      expect(Llms::Service).not_to receive(:summarize)

      result = described_class.fetch_metadata('https://example.com')
      expect(result[:title]).to eq('Test')
    end
  end
end
