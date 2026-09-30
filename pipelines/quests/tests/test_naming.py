import pytest

from tts_cli.naming import (
    filename_for_row,
    filename_from_line_id,
    followup_stem_from_line_id,
    line_id_for_row,
    subfolder_from_line_id,
)

QUEST = {"quest": "5", "source": "accept",
         "templateText_race_gender_hash": "deadbeef", "player_gender": None}
QUEST_F = {"quest": "5", "source": "accept",
           "templateText_race_gender_hash": "deadbeef", "player_gender": "f"}
GOSSIP = {"quest": "", "source": "gossip",
          "templateText_race_gender_hash": "abc123", "player_gender": None}
GOSSIP_M = {"quest": "", "source": "gossip",
            "templateText_race_gender_hash": "abc123", "player_gender": "m"}
# A follow-up row carries its quest, and a float id: extract appends it to a DataFrame whose
# other rows have no broadcast_text_id, so pandas stores the column as float64.
FOLLOWUP = {"quest": 54, "source": "followup", "templateText_race_gender_hash": "feedface",
            "broadcast_text_id": 4377.0, "voice_name": "dwarf-male-standard",
            "player_gender": None}
FOLLOWUP_F = {**FOLLOWUP, "player_gender": "f"}


def test_quest_filename():
    assert filename_for_row(QUEST) == "5-accept"


def test_gendered_quest_filename():
    assert filename_for_row(QUEST_F) == "f-5-accept"


def test_gossip_filename_is_the_hash():
    assert filename_for_row(GOSSIP) == "abc123"


def test_gendered_gossip_filename():
    assert filename_for_row(GOSSIP_M) == "m-abc123"


def test_line_ids():
    assert line_id_for_row(QUEST) == "q:5:accept"
    assert line_id_for_row(QUEST_F) == "q:5:accept:f"
    assert line_id_for_row(GOSSIP) == "g:abc123"
    assert line_id_for_row(GOSSIP_M) == "g:abc123:m"


def test_followup_is_named_after_its_words_and_voice_not_its_quest():
    assert filename_for_row(FOLLOWUP) == "4377-dwarf-male-standard"
    assert filename_for_row(FOLLOWUP_F) == "f-4377-dwarf-male-standard"
    assert line_id_for_row(FOLLOWUP) == "f:4377:dwarf-male-standard"
    assert line_id_for_row(FOLLOWUP_F) == "f:4377:dwarf-male-standard:f"


def test_followup_in_a_model_voice():
    # tts_cli.flavors.model_voice: a speaker with no humanoid display is voiced by its model.
    row = {**FOLLOWUP, "broadcast_text_id": 3475.0, "voice_name": "model-29"}
    assert line_id_for_row(row) == "f:3475:model-29"
    assert filename_for_row(row) == "3475-model-29"
    assert filename_for_row({**row, "player_gender": "m"}) == "m-3475-model-29"
    assert filename_from_line_id("f:3475:model-29:f") == "f-3475-model-29"
    assert followup_stem_from_line_id("f:3475:model-29:f") == "3475-model-29"
    assert subfolder_from_line_id("f:3475:model-29") == "followup"


def test_followup_voice_without_a_flavor():
    row = {**FOLLOWUP, "voice_name": "bloodelf-male"}
    assert line_id_for_row(row) == "f:4377:bloodelf-male"
    assert filename_from_line_id(line_id_for_row(row)) == "4377-bloodelf-male"


def test_followup_lookup_stem_drops_the_gender_prefix():
    # The addon adds m-/f- itself, as for a gossip hash.
    assert followup_stem_from_line_id("f:4377:dwarf-male-standard:f") == "4377-dwarf-male-standard"
    with pytest.raises(ValueError):
        followup_stem_from_line_id("g:abc123")


@pytest.mark.parametrize("row", [QUEST, QUEST_F, GOSSIP, GOSSIP_M, FOLLOWUP, FOLLOWUP_F])
def test_line_id_round_trips_to_filename(row):
    assert filename_from_line_id(line_id_for_row(row)) == filename_for_row(row)


def test_subfolder():
    assert subfolder_from_line_id("q:5:accept") == "quests"
    assert subfolder_from_line_id("g:abc123:m") == "gossip"
    assert subfolder_from_line_id("f:4377:dwarf-male-standard") == "followup"


def test_rejects_unknown_line_id():
    with pytest.raises(ValueError):
        filename_from_line_id("x:nonsense")
    with pytest.raises(ValueError):
        subfolder_from_line_id("x:nonsense")
