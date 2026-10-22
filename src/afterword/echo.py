"""Removing the other side's voice from your microphone track.

Without headphones, your mic also hears the call coming out of your speakers, so their words
show up twice: once on their track and again, at about the same moment, on yours. Their track
is a clean copy of that audio, so a run of words in one of your segments that matches the
words they were saying at that moment is speaker bleed, not you.

One Whisper segment on your track often holds both their echoed sentence and your answer
("…tell me about a time you shipped something difficult. Sure. At my last job…"), so the
matching happens word by word inside each segment rather than dropping whole segments.
"""

import re
from dataclasses import dataclass
from difflib import SequenceMatcher

from afterword.transcript import Segment

# Only compare against what they said within this many seconds of your segment.
NEARBY_SECONDS = 2.0
# One or two matching words could be you repeating them ("Thanks, Dana"); three in a row
# at the same moment is bleed.
MIN_MATCHING_WORDS = 3
# Leftover scraps between two echoed runs, usually a word Whisper heard slightly
# differently on each track ("six" vs "6"), are dropped too when they're this short.
MAX_SCRAP_WORDS = 2


@dataclass(frozen=True)
class TheirWord:
    text: str
    segment: Segment


def remove_echo(mine: list[Segment], theirs: list[Segment]) -> list[Segment]:
    """Returns `mine` without the words that are their voice bleeding into my mic."""
    cleaned = []
    for segment in mine:
        nearby = [
            their_segment for their_segment in theirs
            if their_segment.start - NEARBY_SECONDS <= segment.end
            and their_segment.end + NEARBY_SECONDS >= segment.start
        ]
        without_echo = remove_echo_from_segment(segment, nearby)
        if without_echo is not None:
            cleaned.append(without_echo)
    return cleaned


def remove_echo_from_segment(segment: Segment, nearby: list[Segment]) -> Segment | None:
    my_words = segment.text.split()
    their_words = [TheirWord(word, their_segment) for their_segment in nearby for word in their_segment.text.split()]
    if not their_words:
        return segment

    is_echo = [False] * len(my_words)
    last_echoed_word_of: dict[int, TheirWord] = {}
    matcher = SequenceMatcher(
        a=[normalize(word.text) for word in their_words],
        b=[normalize(word) for word in my_words],
        autojunk=False,
    )
    for match in matcher.get_matching_blocks():
        whole_segment = match.size == len(my_words)
        if match.size < MIN_MATCHING_WORDS and not whole_segment:
            continue
        for offset in range(match.size):
            is_echo[match.b + offset] = True
        last_echoed_word_of[match.b] = their_words[match.a + match.size - 1]

    mark_scraps_between_echoes(is_echo)
    kept = [word for word, echo in zip(my_words, is_echo) if not echo]
    if not kept:
        return None

    start = segment.start
    if is_echo[0] and 0 in last_echoed_word_of:
        # The segment opened with their voice; you started talking once they finished.
        start = min(max(start, last_echoed_word_of[0].segment.end), segment.end)
    return Segment(segment.speaker, start, segment.end, " ".join(kept))


def mark_scraps_between_echoes(is_echo: list[bool]) -> None:
    """Marks short runs of kept words that sit between two echoed runs."""
    index = 0
    while index < len(is_echo):
        if is_echo[index]:
            index += 1
            continue
        run_end = index
        while run_end < len(is_echo) and not is_echo[run_end]:
            run_end += 1
        surrounded = index > 0 and run_end < len(is_echo)
        if surrounded and run_end - index <= MAX_SCRAP_WORDS:
            for scrap in range(index, run_end):
                is_echo[scrap] = True
        index = run_end


def normalize(word: str) -> str:
    return re.sub(r"[^\w]", "", word.lower())
