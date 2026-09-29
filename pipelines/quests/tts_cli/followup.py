"""The lines an NPC says in chat right after a quest is accepted or turned in.

Read out of the world DB once, here, and used twice: tools/export_followup_lines.py writes
them to addons/SpokenQuests/FollowupLines.lua, which the addon matches arriving /say and /yell
against, and tts_cli/corpus.py turns them into corpus rows (source "followup") so they are
voiced and shipped like every other line. Two readers of one extraction, so the addon can
never be armed for a line the corpus has no audio for, or the other way round.

WHERE THEY COME FROM. vmangos runs quest_start_scripts / quest_end_scripts when a quest is
accepted / completed; a row with command 0 (TALK) makes somebody say broadcast_text.dataint,
`delay` seconds after the event, in chat type `datalong`. The script a quest runs is named by
quest_template.StartScript / CompleteScript and is usually, not always, the quest's own id:
the Scarlet Crusade supply quests share one, and quest 8984 runs 9028's.

WHO SPEAKS. The script's source is the quest ender (end) or giver (start). A non-zero
target_type finds a creature near it - 10 by entry, 11 by spawn guid - and that creature only
becomes the speaker when data_flags swaps the final targets (0x02); otherwise the ender speaks
*to* it. So 0x02 decides the speaker, not target_type alone.

A quest with several enders is where the two readers part. The addon rejects a line whose NPC
is not the recorded speaker, so picking one would silence the line at every other ender:
`speaker` stays unset and the text alone decides. The corpus has the opposite need - a line
with no speaker has no voice and is never recorded - so `speakers` lists every candidate, and
each gets a row and, where their voices differ, a clip of its own. Anything unresolvable - a
gameobject ender, an item-started quest - leaves both empty rather than guess, because a wrong
voice is worse than the addon's fallback.

WHAT IS LEFT OUT. Emotes (chat type 2, and say lines written as "%s begins a rite...") have no
voice. A row with dataint2..4 set is a random pick among up to four texts; each alternative is
its own entry at the same delay, since the addon cannot know which one the server chose until
it sees it.
"""

CHAT_TYPES = {0: "say", 1: "yell"}

TARGET_NEAREST_CREATURE_WITH_ENTRY = 10
TARGET_CREATURE_WITH_GUID = 11
SWAP_FINAL_TARGETS = 0x02

#: The corpus `source` of a follow-up line. Frozen with the line ids it names.
SOURCE = "followup"

EVENTS = {
    # event: (script table, quest_template column, relation table naming who runs it)
    "end": ("quest_end_scripts", "CompleteScript", "creature_involvedrelation"),
    "start": ("quest_start_scripts", "StartScript", "creature_questrelation"),
}

# quest_template carries a row per patch for a few quests, and 4265's script changed between
# them; the latest patch is the one a 1.12 server runs.
QUEST_SCRIPTS = """
SELECT entry, Title, {column} FROM (
  SELECT entry, Title, {column},
         ROW_NUMBER() OVER (PARTITION BY entry ORDER BY patch DESC) AS rn
  FROM quest_template
) q WHERE rn = 1 AND {column} <> 0
"""

TALK_ROWS = """
SELECT s.id, s.delay, s.datalong, s.target_type, s.target_param1, s.data_flags,
       s.dataint, s.dataint2, s.dataint3, s.dataint4
FROM {table} s WHERE s.command = 0 AND s.datalong IN ({chat_types})
"""


def fetch(cursor, sql, *args):
    cursor.execute(sql, args)
    return cursor.fetchall()


def resolve_speaker(row, source, guids):
    target_type, param1, flags = row["target_type"], row["target_param1"], row["data_flags"]
    if not target_type or not flags & SWAP_FINAL_TARGETS:
        return source, "source"
    if target_type == TARGET_NEAREST_CREATURE_WITH_ENTRY:
        return param1, "entry"
    if target_type == TARGET_CREATURE_WITH_GUID:
        return guids.get(param1), "guid"
    return None, f"target_type {target_type}"


def collect(connection):
    """{event: {quest: (title, [line, ...])}}, and per event what resolving speakers found.

    A line is {id, speaker, speakers, delay, chat, male, female}: `speaker` is the one the
    addon is given, `speakers` every creature the corpus voices it in - see WHO SPEAKS.
    """
    cursor = connection.cursor()
    texts = {int(e): (m or "", f or "")
             for e, m, f in fetch(cursor, "SELECT entry, male_text, female_text FROM broadcast_text")}
    # A spawn whose id2..id5 are set rolls its entry at spawn time; no single voice fits it.
    guids = {int(g): int(i) for g, i, i2 in fetch(cursor, "SELECT guid, id, id2 FROM creature")
             if not i2}

    result, stats = {}, {}
    for event, (table, column, relation) in EVENTS.items():
        sources = {}
        for creature, quest in fetch(cursor, f"SELECT DISTINCT id, quest FROM {relation} ORDER BY id"):
            sources.setdefault(int(quest), []).append(int(creature))

        rows_by_script = {}
        chat_types = ", ".join(str(t) for t in CHAT_TYPES)
        for r in fetch(cursor, TALK_ROWS.format(table=table, chat_types=chat_types)):
            keys = ("id", "delay", "datalong", "target_type", "target_param1", "data_flags",
                    "dataint", "dataint2", "dataint3", "dataint4")
            row = dict(zip(keys, (int(v) for v in r)))
            rows_by_script.setdefault(row["id"], []).append(row)

        quests, how = {}, {}
        many_sources = []
        for quest, title, script in fetch(cursor, QUEST_SCRIPTS.format(column=column)):
            quest, script = int(quest), int(script)
            candidates = sources.get(quest, [])
            if len(candidates) > 1:
                many_sources.append(quest)
            source = candidates[0] if len(candidates) == 1 else None
            lines = []
            for row in rows_by_script.get(script, []):
                speaker, via = resolve_speaker(row, source, guids)
                # Every ender or giver when it is the script's source that talks; otherwise
                # the one creature the target resolved to, which does not depend on who ran it.
                speakers = list(candidates) if via == "source" else \
                    [speaker] if speaker is not None else []
                for broadcast in (row["dataint"], row["dataint2"], row["dataint3"], row["dataint4"]):
                    if not broadcast or broadcast not in texts:
                        continue
                    male, female = texts[broadcast]
                    male, female = male or female, female or male
                    if not male or male.startswith("%s "):
                        continue
                    lines.append({"id": broadcast, "speaker": speaker, "speakers": speakers,
                                  "delay": row["delay"], "chat": CHAT_TYPES[row["datalong"]],
                                  "male": male, "female": female})
                    key = (via, speaker is not None)
                    how[key] = how.get(key, 0) + 1
            if lines:
                lines.sort(key=lambda line: (line["delay"], line["id"]))
                quests[quest] = (title, lines)
        result[event] = quests
        stats[event] = (how, sorted(q for q in many_sources if q in quests))
    return result, stats


def speaker_entries(result) -> set:
    """Every creature some follow-up line is voiced in."""
    return {speaker for quests in result.values() for _, lines in quests.values()
            for line in lines for speaker in line["speakers"]}


def corpus_rows(result, creatures) -> list:
    """The extraction's dataframe rows for follow-up lines: one per line, quest and speaker.

    `creatures` is {entry: [{name, DisplayRaceID, DisplaySexID, npc_sound_name}, ...]}, the
    voice facts creature quest rows are built from (sql_queries.query_creature_voices). A
    creature missing from it - no humanoid display, so no race to voice it in - gets no row,
    exactly as it gets no quest row. Several entries for one creature are its patch variants
    and each is a row, again as for quest rows.

    A row per quest rather than per line, even where several quests say the same words:
    tts_cli/factions.py picks a line's pack by its quest, so a line said on both sides has to
    be seen on both sides to land in Shared. The file is the same either way - it is named
    after the words and the voice (tts_cli/naming.py).

    The text is the one the speaker's own sex reads, as for gossip: broadcast_text writes a
    male and a female version of what an NPC says, and the male is the fallback where only one
    is written (collect already swapped an empty side for the other).
    """
    seen, rows = set(), []
    for quest, event, title, line in sorted(
            ((quest, event, title, line)
             for event, quests in result.items()
             for quest, (title, lines) in quests.items()
             for line in lines),
            key=lambda item: (item[0], item[1], item[3]["delay"], item[3]["id"])):
        for speaker in line["speakers"]:
            for creature in creatures.get(speaker, ()):
                text = line["male"] if creature["DisplaySexID"] == 0 else line["female"]
                key = (quest, line["id"], speaker, creature["DisplayRaceID"],
                       creature["DisplaySexID"], creature["npc_sound_name"], creature["name"])
                # The start and end scripts of one quest can say the same words, and so can
                # two alternatives of one row; either is one line, not two.
                if key in seen:
                    continue
                seen.add(key)
                rows.append({
                    "source": SOURCE,
                    "quest": quest,
                    "quest_title": title,
                    "text": text,
                    "DisplayRaceID": creature["DisplayRaceID"],
                    "DisplaySexID": creature["DisplaySexID"],
                    "npc_sound_name": creature["npc_sound_name"],
                    "name": creature["name"],
                    "type": "creature",
                    "id": speaker,
                    "original_text": text,
                    "broadcast_text_id": line["id"],
                })
    return rows
