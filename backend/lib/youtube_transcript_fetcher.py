#!/usr/bin/env python3
"""
YouTube Transcript Fetcher
Wrapper script for youtube-transcript-api library
"""

import sys
import json
from youtube_transcript_api import YouTubeTranscriptApi
from youtube_transcript_api._errors import TranscriptsDisabled, NoTranscriptFound, VideoUnavailable

def fetch_transcript(video_id):
    """
    Fetch transcript for a YouTube video
    Returns JSON with transcript text or error
    """
    try:
        # Create API instance
        api = YouTubeTranscriptApi()

        # Try to fetch English transcript first, with fallback to any available language
        # This is a shortcut that handles finding and fetching the transcript
        transcript_obj = api.fetch(video_id, languages=['en'])

        # The FetchedTranscript object is iterable - each item has text, start, duration
        # Extract just the text and join it
        text = ' '.join([snippet.text for snippet in transcript_obj])

        return {
            'success': True,
            'transcript': text,
            'language': transcript_obj.language_code if hasattr(transcript_obj, 'language_code') else 'en'
        }

    except TranscriptsDisabled:
        return {
            'success': False,
            'error': 'Transcripts are disabled for this video'
        }
    except VideoUnavailable:
        return {
            'success': False,
            'error': 'Video is unavailable'
        }
    except NoTranscriptFound:
        return {
            'success': False,
            'error': 'No transcript found for this video'
        }
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(json.dumps({
            'success': False,
            'error': 'Usage: youtube_transcript_fetcher.py <video_id>'
        }))
        sys.exit(1)

    video_id = sys.argv[1]
    result = fetch_transcript(video_id)
    print(json.dumps(result))
