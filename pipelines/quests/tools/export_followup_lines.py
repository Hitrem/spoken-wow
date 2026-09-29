"""The lines an NPC says in chat right after a quest is accepted or turned in.

Writes addons/SpokenQuests/FollowupLines.lua, which the addon reads to recognise those lines
as they arrive in /say or /yell and voice them.

WHERE THEY COME FROM. vmangos runs quest_start_scripts / quest_end_scripts when a quest is
accepted / completed; a row with command 0 (TALK) makes somebody say broadcast_text.dataint,
`delay` seconds after the event, in chat type `datalong`. The script a quest runs is named by
quest_template.StartScript / CompleteScript and is usually, not always, the quest's own id:
the Scarlet Crusade supply quests share one, and quest 8984 runs 9028's.

WHO SPEAKS. The script's source is the quest ender (end) or giver (start). A non-zero
target_type finds a creature near it - 10 by entry, 11 by spawn guid - and that creature only
becomes the speaker when data_flags swaps the final targets (0x02); otherwise the ender speaks
*to* it. So 0x02 decides the speaker, not target_type alone. A quest with several enders gets
no speaker from them: the addon rejects a line whose NPC is not the recorded speaker, so
picking one would silence the line at every other ender. Unset, the text alone decides.
Anything unresolvable - a gameobject ender, an item-started quest - leaves the speaker nil
rather than guess one, because a wrong voice is worse than the addon's fallback.

WHAT IS LEFT OUT. Emotes (chat type 2, and say lines written as "%s begins a rite...") have no
voice. A row with dataint2..4 set is a random pick among up to four texts; each alternative is
exported as its own entry at the same delay, since the addon cannot know which one the server
chose until it sees it.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tts_cli.sql_queries import make_connection  # noqa: E402

DEFAULT_OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "..", "..", "..", "addons", "SpokenQuests", "FollowupLines.lua")

CHAT_TYPES = {0: "say", 1: "yell"}

TARGET_NEAREST_CREATURE_WITH_ENTRY = 10
TARGET_CREATURE_WITH_GUID = 11
SWAP_FINAL_TARGETS = 0x02

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


def export(connection):
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
                for broadcast in (row["dataint"], row["dataint2"], row["dataint3"], row["dataint4"]):
                    if not broadcast or broadcast not in texts:
                        continue
                    male, female = texts[broadcast]
                    male, female = male or female, female or male
                    if not male or male.startswith("%s "):
                        continue
                    lines.append({"id": broadcast, "speaker": speaker, "delay": row["delay"],
                                  "chat": CHAT_TYPES[row["datalong"]], "male": male, "female": female})
                    key = (via, speaker is not None)
                    how[key] = how.get(key, 0) + 1
            if lines:
                lines.sort(key=lambda line: (line["delay"], line["id"]))
                quests[quest] = (title, lines)
        result[event] = quests
        stats[event] = (how, sorted(q for q in many_sources if q in quests))
    return result, stats


def lua_string(text):
    out = []
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append(f"\\{ord(ch):03d}")
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def render(result):
    out = [
        "setfenv(1, VoiceOver)",
        "",
        "-- Generated by pipelines/quests/tools/export_followup_lines.py; do not edit by hand.",
        "-- The world DB's quest start/end scripts make NPCs speak in chat after a quest is",
        "-- accepted or turned in. The client never sees those lines as quest text, so this is",
        "-- how the addon recognises them. speaker is a creature entry, absent when unresolved.",
        "FollowupLines = {",
    ]
    for event in ("end", "start"):
        out.append(f'    [{lua_string(event)}] = {{')
        for quest, (title, lines) in sorted(result[event].items()):
            comment = " ".join((title or "").split())
            out.append(f"        [{quest}] = {{ -- {comment}")
            for line in lines:
                fields = [f"id = {line['id']}"]
                if line["speaker"] is not None:
                    fields.append(f"speaker = {line['speaker']}")
                fields += [f"delay = {line['delay']}", f"chat = {lua_string(line['chat'])}",
                           f"male = {lua_string(line['male'])}"]
                # Absent when it is the male text, which it is for every line today: the
                # copy was a third of the file every login parses, and a second render of
                # the same string on every armed chat message.
                if line["female"] != line["male"]:
                    fields.append(f"female = {lua_string(line['female'])}")
                out.append("            { " + ", ".join(fields) + " },")
            out.append("        },")
        out.append("    },")
    out.append("}")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args()

    result, stats = export(make_connection())
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(render(result))

    print(f"wrote {os.path.normpath(args.out)}")
    for event, quests in result.items():
        count = sum(len(lines) for _, lines in quests.values())
        how, many = stats[event]
        print(f"  {event}: {count} lines across {len(quests)} quests")
        for (via, resolved), n in sorted(how.items()):
            print(f"    speaker via {via}: {n} {'resolved' if resolved else 'nil'}")
        if many:
            print(f"    several possible speakers, left unset: {', '.join(map(str, many))}")
