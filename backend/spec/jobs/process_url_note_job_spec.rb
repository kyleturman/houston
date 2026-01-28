# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProcessUrlNoteJob, type: :job do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user) }

  let(:mock_fetched_data) do
    {
      content: "This is the full web page content. It goes on for many paragraphs...",
      title: "Example Article - A Great Resource",
      fetched_at: Time.current.iso8601,
      metadata: {
        seo: {
          title: "Example Article",
          description: "A great resource for learning"
        },
        og: {
          image: "https://example.com/og-image.jpg",
          title: "Example Article"
        },
        twitter: {
          image: "https://example.com/twitter-image.jpg"
        },
        assets: {
          images: [
            { url: "https://example.com/image1.jpg", alt: "Image 1" },
            { url: "https://example.com/image2.jpg", alt: "Image 2" }
          ]
        }
      }
    }
  end

  let(:mock_summary) do
    "This article discusses important concepts and provides useful examples for learning."
  end

  describe '#perform' do
    context 'with successful processing' do
      it 'fetches web content and generates summary' do
        note = create(:note,
          user: user,
          goal: goal,
          content: "Check this out!",
          metadata: {
            'source_url' => 'https://example.com/article',
            'processing_state' => 'pending',
            'seo' => { 'title' => 'Example Article' }
          }
        )

        # Mock the Web::Service and Llms::Service calls
        expect(Web::Service).to receive(:fetch).with(
          'https://example.com/article',
          clean: true,
          metadata: true,
          images: true
        ).and_return(mock_fetched_data)

        expect(Llms::Service).to receive(:summarize).and_return(mock_summary)

        # Expect SSE broadcast
        expect(Streams::Broker).to receive(:publish)

        described_class.new.perform(note.id)

        note.reload
        expect(note.metadata['web_summary']).to eq(mock_summary)
        expect(note.metadata['processing_state']).to eq('completed')
        expect(note.metadata['images']).to be_present
        expect(note.metadata['og']).to eq({
          'image' => 'https://example.com/og-image.jpg',
          'title' => 'Example Article'
        })
      end

      it 'extracts OG image separately from content images' do
        note = create(:note,
          user: user,
          content: nil,
          metadata: {
            'source_url' => 'https://example.com/article',
            'processing_state' => 'pending'
          }
        )

        # Mock data with no content images but OG image
        fetched_data_with_og = mock_fetched_data.deep_dup
        fetched_data_with_og[:metadata][:assets][:images] = []

        expect(Web::Service).to receive(:fetch).and_return(fetched_data_with_og)
        expect(Llms::Service).to receive(:summarize).and_return(mock_summary)
        allow(Streams::Broker).to receive(:publish)

        described_class.new.perform(note.id)

        note.reload
        # Content images should be empty
        expect(note.metadata['images']).to eq([])
        # But OG image should be extracted separately
        expect(note.metadata['og_image']).to eq({
          'url' => 'https://example.com/og-image.jpg',
          'alt' => 'Preview image'
        })
      end
    end

    context 'with failure scenarios' do
      it 'handles fetch errors gracefully' do
        note = create(:note,
          user: user,
          metadata: {
            'source_url' => 'https://example.com/broken',
            'processing_state' => 'pending'
          }
        )

        expect(Web::Service).to receive(:fetch).and_raise(StandardError.new("Network error"))
        expect(Streams::Broker).to receive(:publish)

        described_class.new.perform(note.id)

        note.reload
        expect(note.metadata['processing_state']).to eq('failed')
        expect(note.metadata['web_summary']).to be_nil
      end

      it 'handles summarization errors gracefully' do
        note = create(:note,
          user: user,
          metadata: {
            'source_url' => 'https://example.com/article',
            'processing_state' => 'pending'
          }
        )

        expect(Web::Service).to receive(:fetch).and_return(mock_fetched_data)
        expect(Llms::Service).to receive(:summarize).and_raise(StandardError.new("LLM error"))
        expect(Streams::Broker).to receive(:publish)

        described_class.new.perform(note.id)

        note.reload
        expect(note.metadata['processing_state']).to eq('failed')
      end

      it 'returns early if note not found' do
        expect(Web::Service).not_to receive(:fetch)

        described_class.new.perform(99999) # Non-existent ID
      end

      it 'returns early if note has no source_url' do
        note = create(:note, user: user, content: "Regular note")

        expect(Web::Service).not_to receive(:fetch)

        described_class.new.perform(note.id)
      end
    end

    context 'SSE broadcasting' do
      it 'broadcasts note_updated event on success' do
        note = create(:note,
          user: user,
          metadata: {
            'source_url' => 'https://example.com/article',
            'processing_state' => 'pending'
          }
        )

        allow(Web::Service).to receive(:fetch).and_return(mock_fetched_data)
        allow(Llms::Service).to receive(:summarize).and_return(mock_summary)

        expect(Streams::Broker).to receive(:publish) do |channel, payload|
          expect(channel).to eq("global:user:#{user.id}")
          expect(payload[:event]).to eq('note_updated')
          expect(payload[:data][:id]).to eq(note.id.to_s)
        end

        described_class.new.perform(note.id)
      end

      it 'broadcasts note_updated event even on failure' do
        note = create(:note,
          user: user,
          metadata: {
            'source_url' => 'https://example.com/broken',
            'processing_state' => 'pending'
          }
        )

        allow(Web::Service).to receive(:fetch).and_raise(StandardError.new("Error"))

        expect(Streams::Broker).to receive(:publish)

        described_class.new.perform(note.id)
      end
    end
  end
end
