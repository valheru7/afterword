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
    mark_matching_runs(segment, my_words, list(range(len(my_words))), their_words, is_echo, last_echoed_word_of)
    # Whisper writes "um" and "uh" on one track and drops them on the other, so one stray
    # filler can split an echoed run into pieces too short to count. A second pass without
    # the fillers catches those; the first pass stays, since a filler that is on both
    # tracks ("Um, I checked…") is itself evidence of an echo.
    my_spoken = [index for index, word in enumerate(my_words) if not is_filler(word)]
    their_spoken = [word for word in their_words if not is_filler(word.text)]
    mark_matching_runs(
        segment, my_words, my_spoken, their_spoken, is_echo, last_echoed_word_of, short_echo_must_overlap=True
    )

    mark_scraps_between_echoes(is_echo)
    mark_fillers_before_opening_echo(my_words, is_echo)
    kept = [word for word, echo in zip(my_words, is_echo) if not echo]
    if not kept or (any(is_echo) and all(is_filler(word) for word in kept)):
        # Nothing left, or only an "um" or two from around their words.
        return None

    start = segment.start
    first_kept = is_echo.index(False)
    opening_echoes = [index for index in last_echoed_word_of if index < first_kept]
    if opening_echoes:
        # The segment opened with their voice; you started talking once they finished.
        opening_echo_end = max(last_echoed_word_of[index].segment.end for index in opening_echoes)
        start = min(max(start, opening_echo_end), segment.end)
    return Segment(segment.speaker, start, segment.end, " ".join(kept))


def mark_matching_runs(
    segment: Segment,
    my_words: list[str],
    my_indices: list[int],
    their_words: list[TheirWord],
    is_echo: list[bool],
    last_echoed_word_of: dict[int, TheirWord],
    short_echo_must_overlap: bool = False,
) -> None:
    """Marks runs of `my_words` (only those at `my_indices`) that match their words in order.

    A run counts once it's MIN_MATCHING_WORDS long, or when it's every word compared. Words
    of mine between a run's first and last word that weren't compared (fillers) are marked too.
    With `short_echo_must_overlap`, a shorter whole-segment run needs two words and only counts
    while they're still talking: an echo happens as they speak, while "Uh, thank you." right after their "Okay,
    thank you." is you answering.
    """
    matcher = SequenceMatcher(
        a=[normalize(word.text) for word in their_words],
        b=[normalize(my_words[index]) for index in my_indices],
        autojunk=False,
    )
    for match in matcher.get_matching_blocks():
        if match.size == 0:
            continue
        their_last_word = their_words[match.a + match.size - 1]
        if match.size < MIN_MATCHING_WORDS:
            whole_segment = match.size == len(my_indices)
            if not whole_segment:
                continue
            # One word ("okay", "right") said while they talk is usually you, not an echo.
            if short_echo_must_overlap and (match.size < 2 or not overlaps(segment, their_last_word.segment)):
                continue
        first, last = my_indices[match.b], my_indices[match.b + match.size - 1]
        for index in range(first, last + 1):
            is_echo[index] = True
        last_echoed_word_of[first] = their_last_word


def overlaps(mine: Segment, theirs: Segment) -> bool:
    return mine.start < theirs.end and theirs.start < mine.end


def mark_fillers_before_opening_echo(my_words: list[str], is_echo: list[bool]) -> None:
    """An "um" just before their echoed words, at the very start of a segment, goes with them."""
    for index, word in enumerate(my_words):
        if not is_filler(word):
            if is_echo[index]:
                for filler in range(index):
                    is_echo[filler] = True
            return


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


# Hesitation sounds, which Whisper writes on one track and leaves out on the other.
FILLERS = {"um", "umm", "uh", "uhh", "uhm", "hmm", "mm", "mhm", "er", "ah"}


def is_filler(word: str) -> bool:
    return normalize(word) in FILLERS
