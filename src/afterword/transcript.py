"""Turning per-track transcription segments into one readable, speaker-labeled transcript."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Segment:
    speaker: str
    start: float  # seconds from the start of the session
    end: float
    text: str


def merge_tracks(tracks: list[list[Segment]]) -> list[Segment]:
    """Interleaves every track's segments in the order they were spoken."""
    segments = [segment for track in tracks for segment in track]
    return sorted(segments, key=lambda segment: (segment.start, segment.speaker))


def format_transcript(segments: list[Segment]) -> str:
    """One paragraph per turn: consecutive segments from the same speaker are joined."""
    turns: list[tuple[Segment, list[str]]] = []
    for segment in segments:
        if turns and turns[-1][0].speaker == segment.speaker:
            turns[-1][1].append(segment.text)
        else:
            turns.append((segment, [segment.text]))

    lines = [f"[{format_timestamp(first.start)}] {first.speaker}: {' '.join(texts)}" for first, texts in turns]
    return "\n\n".join(lines)


def format_timestamp(seconds: float) -> str:
    total = int(seconds)
    hours, remainder = divmod(total, 3600)
    minutes, secs = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"
