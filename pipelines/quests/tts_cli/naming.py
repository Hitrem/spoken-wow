"""Single source of truth for voiceline file naming and identity.

Filenames are load-bearing: the addon resolves a sound by looking its filename up in
SoundLengthLookupByFileName, so a name that differs by one character silently plays
nothing. Every filename in this project is derived here and nowhere else.

    quest lines     {questID}-{accept|complete}      optional m-/f- prefix
    gossip lines    md5(original_text+race+gender)   optional m-/f- prefix
    follow-up lines {broadcastTextID}-{voice}        optional m-/f- prefix

lineId is a stable handle used by the corpus, the audio store and the web app. It is
deliberately not the filename, so references survive a naming change.

    q:{questID}:{source}[:{m|f}]
    g:{hash}[:{m|f}]
    f:{broadcastTextID}:{voice}[:{m|f}]

A follow-up line - what an NPC says in chat after a quest is accepted or turned in, see
tts_cli/followup.py - is named after its words and the voice saying them, not after the quest
and not after md5(text + race + gender) the way gossip is. The words already have an id,
broadcast_text's, which the addon is handed by its own export; and the voice is the whole
voice, flavor included, because the rule for sharing a recording is that the same words share
a clip only among NPCs that sound alike. A quest file or a gossip hash is shared across
flavors and forces them to agree on one (tts_utils.resolve_flavors); this one never needs to.
"""

FOLLOWUP = "followup"


def followup_stem(broadcast_text_id, voice: str) -> str:
    """The follow-up filename before any player-gender prefix, e.g. '4377-dwarf-male-standard'.

    int() because the id reaches here from a DataFrame column that holds NaN for every
    non-follow-up row, which makes pandas carry it as a float.
    """
    return f"{int(broadcast_text_id)}-{voice}"


def filename_for_row(row) -> str:
    """Filename (without extension) the generator would produce for a dataframe row."""
    # Follow-up first: its row carries a quest, and would otherwise be named after it.
    if row["source"] == FOLLOWUP:
        base = followup_stem(row["broadcast_text_id"], row["voice_name"])
    elif row["quest"]:
        base = f'{row["quest"]}-{row["source"]}'
    else:
        base = row["templateText_race_gender_hash"]
    if row["player_gender"]:
        base = f'{row["player_gender"]}-{base}'
    return base


def line_id_for_row(row) -> str:
    """Stable identity for a dataframe row."""
    if row["source"] == FOLLOWUP:
        parts = ["f", str(int(row["broadcast_text_id"])), row["voice_name"]]
    elif row["quest"]:
        parts = ["q", str(row["quest"]), row["source"]]
    else:
        parts = ["g", row["templateText_race_gender_hash"]]
    if row["player_gender"]:
        parts.append(row["player_gender"])
    return ":".join(parts)


def filename_from_line_id(line_id: str) -> str:
    """Inverse of line_id_for_row, as far as the filename is concerned."""
    kind, *rest = line_id.split(":")
    if kind == "q":
        quest, source, *gender = rest
        base = f"{quest}-{source}"
    elif kind == "g":
        hash_, *gender = rest
        base = hash_
    elif kind == "f":
        broadcast, voice, *gender = rest
        base = followup_stem(broadcast, voice)
    else:
        raise ValueError(f"unknown lineId kind {kind!r} in {line_id!r}")
    if gender:
        base = f"{gender[0]}-{base}"
    return base


def gossip_hash_from_line_id(line_id: str) -> str:
    """The bare text hash for a gossip line, without any m-/f- prefix.

    Gossip lookup tables store the unprefixed hash: the addon adds the player's gender
    prefix at resolve time (DataModules:AddPlayerGenderToFilename) and falls back to the
    bare name, so storing a prefixed hash would make the line unreachable for the other
    gender.
    """
    kind, *rest = line_id.split(":")
    if kind != "g":
        raise ValueError(f"{line_id!r} is not a gossip line")
    return rest[0]


def followup_stem_from_line_id(line_id: str) -> str:
    """A follow-up line's filename without any m-/f- prefix, for FollowupLookup.

    Unprefixed for gossip_hash_from_line_id's reason: the addon adds the player's gender
    prefix when it resolves the file, and falls back to the bare name.
    """
    kind, *rest = line_id.split(":")
    if kind != "f":
        raise ValueError(f"{line_id!r} is not a follow-up line")
    return followup_stem(rest[0], rest[1])


def subfolder_from_line_id(line_id: str) -> str:
    """Which sounds/ subdirectory a line lives in."""
    kind = line_id.split(":", 1)[0]
    if kind == "q":
        return "quests"
    if kind == "g":
        return "gossip"
    if kind == "f":
        return FOLLOWUP
    raise ValueError(f"unknown lineId kind {kind!r} in {line_id!r}")
