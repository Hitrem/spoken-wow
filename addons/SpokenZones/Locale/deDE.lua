-- deDE. Empty: nothing has been translated yet.
--
-- Every key in Locale/enUS.lua belongs here, with the same positional format
-- arguments (%1$s) in whatever order this language needs them. Anything missing
-- falls back to English at runtime, and the shortfall is what keeps this language
-- out of the switcher -- see tools/locale/build-languages.mjs.

local _, SpokenZones = ...

if GetLocale() ~= "deDE" then
	return
end

local L = {}

L.OPT_NOTE = "Lore für Zonen und Unterzonen auf der Weltkarte und Minikarte. Text von warcraft.wiki.gg, CC BY-SA 4.0."
L.OPT_SECTION_MAP = "Weltkarte"
L.OPT_MAP_PANEL = "Lore-Fenster neben der Karte zeigen"
L.OPT_MAP_PANEL_TIP = "Das Fenster wird ausgeblendet, solange die Karte maximiert ist, da es sonst außerhalb des Bildschirms läge."
L.OPT_HOVER = "Lore-Tooltip beim Darüberfahren zeigen"
L.OPT_HOVER_TIP = "Fahre über eine Zone auf einer Kontinentkarte oder eine Unterzone auf einer Zonenkarte. Unterdrückt, solange der Zeiger über einem Karten-Pin steht."
L.OPT_PANEL_LEFT = "Fenster links neben der Karte platzieren"
L.OPT_PANEL_WIDTH = "Fensterbreite"
L.OPT_FONT_SIZE = "Schriftgröße"
L.OPT_SECTION_MINIMAP = "Minikarte"
L.OPT_MINIMAP_BUTTON = "Minikartenschaltfläche zeigen"
L.OPT_MINIMAP_BUTTON_TIP = "Linksklick öffnet das Lore-Fenster, Rechtsklick öffnet diese Einstellungen."
L.OPT_SECTION_NARRATION = "Vertonung"
L.OPT_PLAY_BUTTON = "Abspielen-Schaltfläche in Lore-Texten zeigen"
L.OPT_PLAY_BUTTON_TIP = "Liest die Lore vor. Benötigt ein Spoken-Zones-Audio-Begleitaddon; ohne eines erscheint die Schaltfläche nicht."
L.OPT_AUTOPLAY = "Zone beim Entdecken vertonen"
L.OPT_AUTOPLAY_TIP = "Wird durch die entdeckung des Spiels selbst ausgelöst -- in dem Moment, in dem „Durotar entdeckt“ erscheint. Einmal pro Charakter, denn dann feuert das Spiel es."
L.OPT_AUTOPLAY_SUB = "Entdeckte Unterzonen ebenfalls vertonen"
L.OPT_AUTOPLAY_SUB_TIP = "Die meisten Entdeckungen sind Unterzonen -- ein Spaziergang durch Elwynn löst mehrere aus. Sie werden angereiht, nicht unterbrochen, also deaktiviere dies nur, wenn die Vertonung sich pausenlos anfühlt."
L.OPT_AUTOPLAY_EXPLORED = "Auch schon vor Installation erkundete Gebiete vertonen"
L.OPT_AUTOPLAY_EXPLORED_TIP = "Das Spiel meldet eine Entdeckung einmal pro Charakter, für immer -- ein Charakter, der Azeroth schon erkundet hat, bekommt daher nie etwas vertont. Aktiviere dies, und Spoken Zones führt stattdessen selbst Buch, weiterhin ein Clip pro Gebiet pro Charakter. /spz forget löscht es."
L.OPT_PACK_NONE = "Es wird nichts vertont. Installiere Spoken Zones Audio, um die Lore vorgelesen zu bekommen."
L.OPT_SECTION_PACKS = "Soundpacks"
L.OPT_VOICE_LANGUAGE = "Vertonungssprache"
L.OPT_VOICE_LANGUAGE_TIP = "Welche Sprache das Soundpack vorliest. „Automatisch“ nutzt die Sprache, die du liest, sonst die deines Spiels. Eine Sprache ist nur zu hören, wenn ein Soundpack darin aufgenommen wurde."
L.OPT_FALLBACK_LANGUAGE = "Ausweichsprache"
L.OPT_FALLBACK_LANGUAGE_TIP = "Was abgespielt wird, wenn kein Pack in deiner gewählten Sprache den Eintrag hat. „Keine“ lässt ihn stumm, statt ihn in einer Sprache zu erzählen, um die du nicht gebeten hast."
L.OPT_FALLBACK_NONE = "Keine (still)"
L.OPT_SECTION_LANGUAGE = "Sprache"
L.OPT_LANG_AUTO_FMT = "Automatisch (%1$s)"
L.OPT_SECTION_TROUBLE = "Fehlersuche"
L.OPT_DEBUG_MAP_CLICK = "Gebietsnamen bei Kartenklick melden"
L.OPT_DEBUG_MAP_CLICK_TIP = "Gibt den rohen Gebietsnamen aus, den der Client meldet, den Schlüssel, zu dem er normalisiert wird, und ob Lore gefunden wurde. Damit findest du eine Unterzone, die einen Alias braucht."
L.OPT_SECTION_FEEDBACK = "Feedback"
L.OPT_REPORT_PROBLEM = "Problem melden"
L.OPT_REPORT_ADDRESS = "Kopiere diese Adresse und öffne sie in deinem Browser, um Feedback zu Spoken Zones zu senden."
L.OPT_REPORT_NOTE = "Auf jedem Lore-Eintrag gibt es eine Melden-Schaltfläche für Probleme mit diesem Eintrag. Diese hier ist für alles andere. Das Spiel kann keinen Link öffnen, also geben beide dir eine Adresse zum Kopieren."
L.MENU_LORE_WINDOW = "Lore-Fenster öffnen"
L.MENU_ZONE_SETTINGS = "Spoken-Zones-Einstellungen"

L.OPT_REPORT_LINE_TIP = "Falsche Lore, schlechte Lesung, falsch ausgesprochener Name -- dafür gibt es hier einen Link."
L.OPT_REPORT_LINE_ADDRESS = "Kopiere diese Adresse und öffne sie in deinem Browser, um ein Problem mit diesem Eintrag zu melden."

L.STOP = "Stopp"
L.AUDIO_STOP_TIP = "Die Vertonung stoppen"
L.AUDIO_READ_TIP = "Diese Lore laut vorlesen"
L.REPORT_BUTTON = "Melden"
L.CONTRIBUTE_BUTTON = "Mitwirken"
L.CONTRIBUTE_BUTTON_TIP_TITLE = "Spoken Zones hat keine Lore für diesen Ort"
L.CONTRIBUTE_BUTTON_TIP = "Wirke mit, indem du ihn beschreibst: was es ist, wer dort lebt, was dort geschah."
L.IN_ZONE_FMT = "in %1$s"
L.LORE_WINDOW_EMPTY = "Wähle links eine Zone. Zonen mit Unterzonen zeigen eine Anzahl; klicke eine an, um sie aufzuklappen."

L.QUEUE_HELD_COMBAT = "Wartet auf Kampfende."
L.QUEUE_HELD_CINEMATIC = "Wartet auf das Ende der Zwischensequenz."
L.QUEUE_HELD_OFF = "Vertonung ist ausgeschaltet."
L.BACK_TO_ZONE = "< Zurück zu %1$s"
L.NO_LORE_FOR = "Noch keine Lore für %1$s aufgenommen."
L.LORE_NOT_WRITTEN = "%1$s ist auf der Karte, aber niemand hat seine Lore geschrieben."
L.MAP_LORE_FOR_FMT = "Lore für %1$s"
L.MAP_SUBZONE_MORE = "klicke eine Unterzone auf der Karte für mehr an"
L.CMD_HEADING = "Befehle (/spokenzones oder /spz):"
L.CMD_STATUS = "  /spz            -- Status für aktuelle Zone und Unterzone"
L.CMD_OPTIONS = "  /spz options    -- öffnet das Einstellungsfenster"
L.CMD_WINDOW = "  /spz window     -- öffnet das durchsuchbare Lore-Fenster"
L.CMD_PANEL = "  /spz panel      -- schaltet das Weltkartenfenster um"
L.CMD_HOVER = "  /spz hover      -- schaltet die Hover-Vorschau um"
L.CMD_PLAY = "  /spz play       -- liest die aktuelle Lore vor"
L.CMD_STOP = "  /spz stop       -- stoppt die Vertonung"
L.CMD_VOICE = "  /spz voice      -- schaltet Vertonung an oder aus"
L.CMD_AUTOPLAY = "  /spz autoplay   -- schaltet das Vertonen entdeckter Gebiete um"
L.CMD_AUDIO = "  /spz audio      -- listet Soundpacks, oder wechseln mit /spz audio <name>"
L.CMD_LANG = "  /spz lang       -- listet Sprachen, oder wechseln mit /spz lang <code> oder auto"
L.CMD_DISCOVER = "  /spz discover   -- tut so, als würde ein Gebiet entdeckt (dev)"
L.CMD_FORGET = "  /spz forget     -- vergisst, was dieser Charakter schon vertont bekam"
L.CMD_BAR = "  /spz bar        -- bewegt den Player zurück in die Bildschirmmitte"
L.CMD_MINIMAP = "  /spz minimap    -- zeigt oder versteckt die Minikartenschaltfläche"
L.CMD_DEBUG = "  /spz debug      -- meldet Gebietsnamen bei Kartenklick"
L.CMD_VERIFY = "  /spz verify     -- prüft Daten gegen diesen Client"
L.CMD_DUMP = "  /spz dump       -- listet den Kartenbaum auf (dev)"

L.SUBZONE_COUNT_FMT = "%1$d Unterzonen"

SpokenZones:RegisterStrings("deDE", L)
