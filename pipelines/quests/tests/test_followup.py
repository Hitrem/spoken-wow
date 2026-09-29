from tts_cli.followup import corpus_rows, speaker_entries


def _line(broadcast, speakers, male="Well done.", female=None, delay=0):
    return {"id": broadcast, "speaker": speakers[0] if len(speakers) == 1 else None,
            "speakers": speakers, "delay": delay, "chat": "say",
            "male": male, "female": female or male}


def _voice(name, race=3, sex=0, sound="DwarfMaleStandardNPCGreetings"):
    return {"name": name, "DisplayRaceID": race, "DisplaySexID": sex, "npc_sound_name": sound}


CREATURES = {
    1: [_voice("Belgrum")],
    2: [_voice("Mountaineer", sound="DwarfMaleGrimNPCGreetings")],
    3: [_voice("Sister", race=1, sex=1, sound="HumanFemaleStandardNPCGreetings")],
}


def test_a_quest_with_several_enders_is_voiced_in_each():
    # The addon's export leaves `speaker` unset for these; the corpus cannot, since a line
    # nobody speaks is never recorded.
    result = {"end": {10: ("Two Enders", [_line(500, [1, 2])])}}

    rows = corpus_rows(result, CREATURES)

    assert [(r["id"], r["name"]) for r in rows] == [(1, "Belgrum"), (2, "Mountaineer")]
    assert {r["source"] for r in rows} == {"followup"}
    assert {r["broadcast_text_id"] for r in rows} == {500}
    assert {r["quest"] for r in rows} == {10}


def test_a_line_shared_by_two_quests_is_a_row_under_each():
    # factions.pack_of_line reads the quest, so both sides have to see the line.
    result = {"end": {10: ("A", [_line(500, [1])]), 11: ("B", [_line(500, [1])])}}

    assert [r["quest"] for r in corpus_rows(result, CREATURES)] == [10, 11]


def test_the_speakers_sex_picks_the_text():
    result = {"end": {10: ("A", [_line(500, [1, 3], male="Thanks, lad.",
                                       female="Thanks, dear.")])}}

    texts = {r["name"]: (r["text"], r["original_text"]) for r in corpus_rows(result, CREATURES)}

    assert texts == {"Belgrum": ("Thanks, lad.", "Thanks, lad."),
                     "Sister": ("Thanks, dear.", "Thanks, dear.")}


def test_a_speaker_with_no_voice_facts_is_left_out():
    # No humanoid display, so no race - and no quest row either.
    result = {"end": {10: ("A", [_line(500, [99]), _line(501, [])])}}

    assert corpus_rows(result, CREATURES) == []


def test_the_same_words_twice_for_one_quest_are_one_row():
    # A quest's start and end scripts can say the same thing, and so can two alternatives.
    result = {"end": {10: ("A", [_line(500, [1]), _line(500, [1], delay=3)])},
              "start": {10: ("A", [_line(500, [1])])}}

    assert len(corpus_rows(result, CREATURES)) == 1


def test_speaker_entries_is_every_candidate():
    result = {"end": {10: ("A", [_line(500, [1, 2])])}, "start": {11: ("B", [_line(7, [3])])}}

    assert speaker_entries(result) == {1, 2, 3}
