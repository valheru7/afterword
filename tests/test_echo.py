from afterword.echo import remove_echo
from afterword.transcript import Segment

QUESTION = Segment("Them", 13.0, 18.0, "Great. So to start, tell me about a time you shipped something difficult.")


def test_segment_that_is_only_their_voice_is_dropped():
    echo = Segment("Me", 13.1, 18.1, "So to start, tell me about a time you shipped something difficult.")

    assert remove_echo([echo], [QUESTION]) == []


def test_echoed_opening_is_cut_and_start_moves_to_when_they_finished():
    mixed = Segment("Me", 13.1, 30.0, "Great. So to start, tell me about a time you shipped something difficult. Sure. At my last job I migrated our app.")

    assert remove_echo([mixed], [QUESTION]) == [Segment("Me", 18.0, 30.0, "Sure. At my last job I migrated our app.")]


def test_a_word_heard_differently_between_two_echoed_runs_is_dropped():
    them = Segment("Them", 40.0, 46.0, "The role is fully remote. The team is six engineers, and the band is 160 to 190.")
    mine = Segment("Me", 40.1, 46.1, "The role is fully remote. The team is 6 engineers, and the band is 160 to 190.")

    assert remove_echo([mine], [them]) == []


def test_repeating_a_couple_of_their_words_is_kept():
    them = Segment("Them", 1.0, 6.0, "Hi, thanks for making time today, I'm Dana.")
    mine = Segment("Me", 7.0, 9.0, "Thanks, Dana. Happy to be here.")

    assert remove_echo([mine], [them]) == [mine]


def test_quoting_them_much_later_is_kept():
    mine = Segment("Me", 300.0, 305.0, "You asked about a time you shipped something difficult, so here's another.")

    assert remove_echo([mine], [QUESTION]) == [mine]


def test_short_echo_matching_the_whole_segment_is_dropped():
    them = Segment("Them", 31.0, 31.5, "Nice.")
    echo = Segment("Me", 31.1, 31.6, "Nice.")

    assert remove_echo([echo], [them]) == []
