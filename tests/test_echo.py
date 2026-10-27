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


def test_echo_split_by_a_filler_is_dropped():
    them = Segment("Them", 95.0, 100.0, "He, unfortunately, has a very large project he had to take on.")
    echo = Segment("Me", 95.2, 96.0, "um he unfortunately")

    assert remove_echo([echo], [them]) == []


def test_fillers_inside_an_echoed_run_go_with_it():
    them = Segment("Them", 10.0, 14.0, "We have the salary range provided as about 100k to 181.")
    mixed = Segment("Me", 10.1, 20.0, "salary uh range provided as um about 100k to 181 okay that's lower than I expected")

    assert remove_echo([mixed], [them]) == [Segment("Me", 14.0, 20.0, "okay that's lower than I expected")]


def test_filler_on_both_tracks_still_counts_toward_a_match():
    them = Segment("Them", 50.0, 55.0, "Um, I checked, uh, test coverage yesterday.")
    echo = Segment("Me", 50.1, 52.0, "Um, I checked")

    assert remove_echo([echo], [them]) == []


def test_your_own_filler_with_one_of_their_words_is_kept():
    them = Segment("Them", 20.0, 24.0, "So what would you do next?")
    mine = Segment("Me", 24.5, 25.0, "So, um,")

    assert remove_echo([mine], [them]) == [mine]


def test_a_lone_filler_with_no_echo_is_kept():
    them = Segment("Them", 20.0, 24.0, "What would you do next?")
    mine = Segment("Me", 24.5, 25.0, "Um,")

    assert remove_echo([mine], [them]) == [mine]


def test_your_short_reply_after_they_finish_is_kept():
    them = Segment("Them", 29.0, 30.4, "Okay, thank you.")
    mine = Segment("Me", 30.5, 31.5, "Uh, thank you.")

    assert remove_echo([mine], [them]) == [mine]


def test_filler_before_an_echoed_opening_goes_with_it():
    them = Segment("Them", 95.0, 97.0, "He, unfortunately, has a very large project.")
    mixed = Segment("Me", 95.1, 99.0, "um he unfortunately has a very large project okay sure")

    assert remove_echo([mixed], [them]) == [Segment("Me", 97.0, 99.0, "okay sure")]


def test_one_word_backchannel_while_they_talk_is_kept():
    them = Segment("Them", 60.0, 66.0, "Okay, so then the staff pair the card reader with the iPad.")
    mine = Segment("Me", 60.5, 61.0, "Um, uh, okay.")

    assert remove_echo([mine], [them]) == [mine]
