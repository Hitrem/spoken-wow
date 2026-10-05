# DialogueUI bridge

[DialogueUI](https://www.curseforge.com/wow/addons/dialogueui) replaces the quest and gossip
frames with its own window. While that window is open it also hides the rest of the interface,
which hides Spoken's window or subtitles. `addons/Spoken_Quests/UI/DialogueUIBridge.lua`
brings back what was hidden, inside DialogueUI's window:

- **Mark the words being read.** DialogueUI's own quest and gossip text follows the line the
  way Spoken's captions do. Spoken's **Type Words Out** types it out as the voice reaches each
  word, and its **Highlight Words** lights the word being read. Either, both or neither: the
  bridge follows those two settings on Spoken's page and has none of its own. The light is
  gold on DialogueUI's dark theme and deep red on its parchment theme, where gold is hard to read.
- **Keep the words in view.** Long text scrolls to the paragraph being read whenever reading
  moves to another paragraph.
- **Show Spoken over DialogueUI.** The window or the subtitles stay on screen in the place they
  were left, with their controls. They can't be dragged until DialogueUI closes.
- **Use DialogueUI's Play button.** Spoken Quests registers as DialogueUI's voiceover provider,
  so DialogueUI's text-to-speech button plays the recording. The button appears only when
  text-to-speech is turned on in DialogueUI's settings.

All but **Show Spoken over DialogueUI** are on by default: DialogueUI's window, marked as the
line plays, already shows the words. They sit in the Quests section of Spoken's **DialogueUI** page
(Spoken > DialogueUI), beside the DialogueUI narrator style's settings, added there through
`Spoken:AddDialogueUISettings`; that page's Defaults button resets them too. With a Spoken too
old to have that page, they are a **DialogueUI** section of the Quests page instead. When
something they need is missing they are greyed out with the reason in their tooltip.
`/spq diagnostics` prints one `DialogueUI:` line with the same answer.

## How it works

Nothing in DialogueUI is changed. The module reaches it from outside, through names that are
DialogueUI internals rather than an API:

- `DUIQuestFrame` is the window. Each paragraph of text is a FontString in its
  `fontStringPool`, tagged with `ttsFlag`, or with `isTranslation` for translator addons.
- `HandleQuestDetail`, `HandleQuestProgress`, `HandleQuestComplete`, `HandleQuestGreeting`
  and `HandleGossip` build a page. They are hooked with `hooksecurefunc`, because DialogueUI
  calls them by name (`self[handler](self)`) on every build and rebuild. An item reward
  resolving, a settings change or a repeated `QUEST_DETAIL` all trigger a rebuild.
- `DialogueUIAPI.SetVOProvider` is DialogueUI's one public hook for voiceover addons.

All of these are checked once at login. If any is missing, the module does nothing and the
settings panel says that DialogueUI's version isn't recognised.

**Timing and matching.** The timing is the captions' own estimate, read through
`Spoken:GetCaption()`, which also says whether Highlight Words and Type Words Out are on. It
is worked out on every call rather than read from the captions, which stop updating while
DialogueUI hides their window. Each line of DialogueUI's text is split with
`Spoken:SplitCaption()`, the same splitter the captions use, so Chinese is matched character
by character. The caption's words are then matched in order against DialogueUI's words:

- A match may skip a few words. This covers the NPC name DialogueUI can put in front of the
  text, and a hint above it.
- Every starting paragraph is tried, because DialogueUI can keep earlier gossip above the
  current page. On a tie, the later paragraph wins.
- Below 60 % of the words matched, the window shows something else, so nothing is marked.
- Only Spoken Quests' own lines are matched. A zone's lore or a book page playing while
  DialogueUI is open leaves its text alone.

**Drawing.** Both marks are made in the paragraph's own text:

- The highlight is a colour code around the word.
- Typing out shows the paragraphs the line covers up to the word being read, and the ones
  after it blank. DialogueUI draws a page the moment the dialog opens, while Spoken Quests
  reads it a moment later (0.1 s for gossip, once a quest has held still for 0.4 s). So when
  a page is about to be read, `Addon:ExpectedLine(event)` gives its line's text as the page
  is built, and its words are blank from the first frame, for up to 1.5 s, until the voice
  reaches them. Shown whole until then, they flashed up and vanished. A page nothing will
  read on its own shows whole at once, as does one opened while another part's line plays. Paragraphs outside the line, such as earlier gossip or the objectives' list
  when the recording does not read it, stay whole. Nothing shows before the voice starts and
  everything once it has finished, as in the captions. A clip with no length is shown whole.

Colour codes take no width, and a left-aligned prefix wraps exactly as the whole paragraph
did. DialogueUI placed every paragraph once, when it built the page, so nothing moves. Words
inside a link are never marked, so a link is never split. The original text is put back when
the line ends, when the window closes or when the setting is turned off, because DialogueUI
reads that text back for its own text-to-speech.

**Hosting the player.** This uses `Spoken:SetPlayerHost(DUIQuestFrame)`:

- The window and the subtitles are reparented with their anchors kept and their scale
  adjusted, so they keep their exact place on screen.
- Their strata is raised above the window. The subtitles pass clicks through to it.
- Dragging is locked, so a position measured in DialogueUI's scale is never saved.

`Spoken:SetPlayerHost(nil)` puts all of it back, the subtitles' own low strata included.

**Play button.** DialogueUI hears the client's quest event before Spoken Quests' recorder
does. So the provider resolves the line from the page DialogueUI says it is showing, through
`Addon:GetVisibleLine(event)`, rather than from the last recorded event. Play does nothing when
the line is already queued, so DialogueUI's autoplay and Spoken Quests' autoplay don't read
it twice. Stop works only while the window is open. DialogueUI also asks the provider to
stop as its window closes, and accepting a quest closes it. That comes from DialogueUI's
"TTS Auto Stop" setting, which is on by default even with its text-to-speech off. Obeying it
would cut every line short at the accept, so whether closing the dialog stops the line is
left to Spoken Quests' own **Stop When Window Closes**.

## Limits

- The timing is an estimate, as for the captions. The recording says "adventurer" where the
  text has the player's name, so the marks can run slightly ahead or behind around a long name.
- A word wrapped in a link or colour by DialogueUI or another addon is never marked.
- Matching relies on DialogueUI showing the client's text. A translator addon's translated
  paragraphs are skipped, and only the original paragraphs, when shown, are marked.
- DialogueUI's text-to-speech reads the paragraphs back from the window. While a paragraph is
  typed part way it would read only that part. With **Use DialogueUI's Play Button** on, the
  button plays the recording instead.
- DialogueUI's internals can change in any release. When they do, the settings say so and
  nothing breaks, but the feature is off until this file catches up.

Tests: `tests/lua/quests_dialogueui_test.lua`, against a fake `DUIQuestFrame`.
