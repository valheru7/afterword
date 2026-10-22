from afterword.transcribe import parse_whisper_json, trim_to_speech
from afterword.transcript import Segment, format_timestamp, format_transcript, merge_tracks


def test_merge_interleaves_tracks_by_start_time():
    me = [Segment("Me", 5.0, 7.0, "Thanks."), Segment("Me", 20.0, 22.0, "Sure.")]
    them = [Segment("Them", 1.0, 4.0, "Hi."), Segment("Them", 10.0, 15.0, "Tell me about yourself.")]

    merged = merge_tracks([me, them])

    assert [segment.text for segment in merged] == ["Hi.", "Thanks.", "Tell me about yourself.", "Sure."]


def test_format_joins_consecutive_segments_from_the_same_speaker():
    segments = [
        Segment("Them", 1.0, 2.0, "Hi."),
        Segment("Them", 2.0, 3.0, "Welcome."),
        Segment("Me", 65.0, 66.0, "Thanks."),
    ]

    assert format_transcript(segments) == "[00:00:01] Them: Hi. Welcome.\n\n[00:01:05] Me: Thanks."


def test_format_timestamp_handles_hours():
    assert format_timestamp(3725.9) == "01:02:05"


def test_parse_whisper_json_converts_milliseconds_and_applies_offset():
    whisper_json = {
        "transcription": [
            {"offsets": {"from": 1500, "to": 3000}, "text": " Hello there."},
            {"offsets": {"from": 3000, "to": 3500}, "text": "  "},
        ]
    }

    segments = parse_whisper_json(whisper_json, "Them", offset_seconds=0.25)

    assert segments == [Segment("Them", 1.75, 3.25, "Hello there.")]


def test_trim_drops_segments_that_are_all_silence():
    hallucination = Segment("Me", 0.0, 30.0, "Thank you.")

    assert trim_to_speech(hallucination, silences=[(0.0, 31.0)]) is None


def test_trim_moves_a_stretched_start_to_where_the_sound_begins():
    # Whisper often starts a segment at the beginning of the silence before it.
    stretched = Segment("Me", 90.0, 98.4, "Thanks, Dana.")

    trimmed = trim_to_speech(stretched, silences=[(85.0, 97.9)])

    assert trimmed == Segment("Me", 97.9, 98.4, "Thanks, Dana.")


def test_trim_keeps_segments_with_no_silence():
    segment = Segment("Them", 3.0, 6.0, "Okay.")

    assert trim_to_speech(segment, silences=[(0.0, 2.0), (7.0, 9.0)]) == segment
