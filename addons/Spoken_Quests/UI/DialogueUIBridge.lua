setfenv(1, VoiceOver)

-- DialogueUI (Peterodox's quest and gossip window, CurseForge "DialogueUI") replaces the
-- Blizzard frames this addon's buttons sit on, and while it is open it hides UIParent -- the
-- Spoken player, and the captions on it, go with it. This puts what they showed into
-- DialogueUI's own window instead:
--
--   * DialogueUI's quest and gossip text follows the line as Spoken's captions do: the words
--     type out as the voice reaches them, the word being read lights up, or both -- whichever
--     of Spoken's Type Words Out and Highlight Words is on (Spoken:GetCaption) -- and long
--     text scrolls to keep the voice in view;
--   * the Spoken player, or its subtitles, can stay on screen over DialogueUI;
--   * DialogueUI's Play button (its text-to-speech button) plays this addon's recording, and
--     its Auto Play decides this addon's autoplay or is kept in sync with it;
--   * the Contribute button, for a line no pack has, sits on DialogueUI's window, and the
--     copy box it opens shows over it (Bridge:Page, UI/ContributeButton.lua).
--
-- Nothing here changes DialogueUI. It is reached from outside: its window is the global
-- DUIQuestFrame, each paragraph of text is a FontString in that frame's fontStringPool, and
-- the Handle* methods that build a page are hooked after the fact. Those names are
-- DialogueUI's internals, not an API, so they are checked once at setup and the whole module
-- stands down, with a note on the settings panel, if any is missing.
--
-- Both marks are made in the paragraph's own text. The highlight is a colour code wrapped
-- round a word; typing out shows the paragraph up to the word being read, and nothing of the
-- paragraphs after it. Colour codes take no width and a left-aligned prefix wraps as the
-- whole did, and DialogueUI placed every paragraph once, when it built the page: nothing
-- moves. The original text is put back when the line ends or the window closes: DialogueUI
-- reads it back for its own text-to-speech.
--
-- Written for Lua 5.0 as far as parsing goes, because addon.xml is shared with the 1.12
-- client (no #, no %): that client has no DialogueUI, and the file returns before any of it
-- runs there.

DialogueUIBridge = { status = "waiting" }
local Bridge = DialogueUIBridge

if Version.IsAnyLegacy then
    Bridge.status = "legacy client"
    return
end

-- The page builders, each a method DialogueUI calls by name: self[handler](self). A rebuild
-- (an item reward resolving, a settings change, QUEST_DETAIL firing twice) runs one again.
local HANDLERS = { "HandleQuestDetail", "HandleQuestProgress", "HandleQuestComplete",
    "HandleQuestGreeting", "HandleGossip" }
-- How many words of DialogueUI's text a caption word may skip to find its match: the NPC
-- name DialogueUI can put in front of the text, a hint, a word that differs.
local LOOKAHEAD = 6
-- Below this share of the caption's words found in the window, the window shows something
-- else -- an earlier page, another NPC's gossip -- and nothing is marked.
local MIN_SHARE = 0.6
-- The captions' gold reads on DialogueUI's dark theme; on its parchment, whose text is dark,
-- gold on tan does not, and a deep red does.
local ON_DARK = "|cffffd100"
local ON_LIGHT = "|cff9c1a1a"
local TICK = 0.05
-- Spoken Quests reads a dialog a moment after it opens -- 0.1s for gossip, once a quest has
-- held still for 0.4s, then once DialogueUI's window has faded in (Bridge:Defer) -- and
-- DialogueUI draws the page at once. Typed out, the words the line is about to read are kept
-- blank from the start (Bridge.Expect), for up to this long: shown whole until the voice
-- began, they flashed up and vanished.
local HOLD = 2.5
-- The longest autoplay waits for DialogueUI's window to fade in: its slowest intro is 0.75s
-- and its text fades in over 0.35s. Past it the line reads anyway.
local WAIT_LIMIT = 1.5
-- Each page builder, by the dialog event Spoken Quests reads its page for.
local EVENTS = { HandleQuestDetail = "QUEST_DETAIL", HandleQuestProgress = "QUEST_PROGRESS",
    HandleQuestComplete = "QUEST_COMPLETE", HandleQuestGreeting = "QUEST_GREETING", HandleGossip = "GOSSIP_SHOW" }
-- DialogueUI's names for the quest pages, as its voiceover provider is told them.
local QUEST_EVENTS = { detail = "QUEST_DETAIL", progress = "QUEST_PROGRESS", completion = "QUEST_COMPLETE" }

local function Config()
    return Addon.db.profile.DialogueUI
end

local function IsLoaded(name)
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return isLoaded and isLoaded(name) and true or false
end

--- Whether DUIQuestFrame still has everything this file reaches for.
local function Recognised()
    local frame = _G.DUIQuestFrame
    if type(frame) ~= "table" or type(frame.fontStringPool) ~= "table" or not frame.ContentFrame then
        return false
    end
    if type(frame.fontStringPool.EnumerateActive) ~= "function" then
        return false
    end
    for _, name in ipairs(HANDLERS) do
        if type(frame[name]) ~= "function" then
            return false
        end
    end
    return true
end

--- Why `feature` (a key of the DialogueUI settings) cannot work, or nil when it can. The
--- settings panel greys the option and shows this.
function Bridge:Problem(feature)
    if not IsLoaded("DialogueUI") then
        return L.OPT_DUI_MISSING
    elseif not (_G.Spoken and Spoken.IsCompatible and Spoken:IsCompatible(1)) then
        return L.OPT_DUI_NO_PLAYER
    elseif not Recognised() then
        return L.OPT_DUI_UNKNOWN
    elseif (feature == "Captions" or feature == "AutoScroll") and not (Spoken.GetCaption and Spoken.SplitCaption) then
        return L.OPT_DUI_OLD_PLAYER
    elseif feature == "ShowPlayer" and not Spoken.SetPlayerHost then
        return L.OPT_DUI_OLD_PLAYER
    elseif (feature == "PlayButton" or feature == "EnableTTS")
        and not (_G.DialogueUIAPI and DialogueUIAPI.SetVOProvider) then
        return L.OPT_DUI_UNKNOWN
    end
end

--------------------------------------------------------------------------------
-- Matching the caption to the window
--------------------------------------------------------------------------------

--- A word as compared: lower case, without ASCII punctuation. nil for a word that cannot be
--- compared -- all punctuation, or carrying an escape sequence (a link, a colour), which
--- DialogueUI's copy may have and the caption's never does, and which must never be split.
function Bridge.Key(text)
    if string.find(text, "|", 1, true) then
        return nil
    end
    local key = string.gsub(string.lower(text), "%p", "")
    if key == "" then
        return nil
    end
    return key
end

--- Mark the words inside a hyperlink (|H...|h[name]|h): the name's inner words carry no
--- escape of their own, and lighting one, or typing up to it, would split the link.
function Bridge.MarkLinks(text, words)
    local from = 1
    while true do
        local s, e = string.find(text, "|H.-|h.-|h", from)
        if not s then
            return words
        end
        for _, word in ipairs(words) do
            if word.last >= s and word.first <= e then
                word.inLink = true
            end
        end
        from = e + 1
    end
end

--- Match the caption's words to the paragraphs' from paragraph `first` on. Each caption word
--- is looked for a few words past the last match; the first only within paragraph `first`.
--- Returns map[i] = { p = paragraph, w = word } for the words found, how many were found,
--- and how many could have been.
function Bridge.AlignFrom(words, paragraphs, first)
    local tokens = {}
    local firstEnd = 0
    for p = first, table.getn(paragraphs) do
        for w, word in ipairs(paragraphs[p].words) do
            table.insert(tokens, { p = p, w = w, key = not word.inLink and Bridge.Key(word.text) or nil })
        end
        if p == first then
            firstEnd = table.getn(tokens)
        end
    end
    local map, found, counted, nextToken = {}, 0, 0, 1
    local total = table.getn(tokens)
    for i, word in ipairs(words) do
        local key = Bridge.Key(word.text)
        if key then
            counted = counted + 1
            local last = math.min(total, found == 0 and firstEnd + LOOKAHEAD or nextToken + LOOKAHEAD)
            for t = nextToken, last do
                if tokens[t].key == key then
                    map[i] = tokens[t]
                    found = found + 1
                    nextToken = t + 1
                    break
                end
            end
        end
    end
    return map, found, counted
end

--- The best match over every starting paragraph, or nil when none is good enough. Every start
--- is tried because DialogueUI can keep earlier gossip above the current page, and a hint
--- above the text; the later start wins a tie, the current gossip being the last. The second
--- value is the span of paragraphs matched, { first, last }: only those are ever typed out.
function Bridge.Align(words, paragraphs)
    local bestMap, bestFound, bestCounted = nil, 0, 0
    for first = 1, table.getn(paragraphs) do
        local map, found, counted = Bridge.AlignFrom(words, paragraphs, first)
        if found > 0 and found >= bestFound then
            bestMap, bestFound, bestCounted = map, found, counted
        end
    end
    if not bestMap or bestFound < math.min(3, bestCounted) or bestFound < bestCounted * MIN_SHARE then
        return nil
    end
    local span
    for _, at in pairs(bestMap) do
        if not span then
            span = { first = at.p, last = at.p }
        else
            span.first, span.last = math.min(span.first, at.p), math.max(span.last, at.p)
        end
    end
    return bestMap, span
end

--- The pair to light for caption word `index`: that word, or the last one before it the
--- window has, and its neighbour in the same paragraph -- the next word, or at the end of a
--- paragraph the one before, as the captions keep the last pair lit at a page boundary.
function Bridge.Pick(map, index)
    if not index then
        return nil
    end
    local lit = index
    while lit > 0 and not map[lit] do
        lit = lit - 1
    end
    if lit == 0 then
        return nil
    end
    local at = map[lit]
    local after, before = map[lit + 1], map[lit - 1]
    if after and after.p == at.p then
        return lit, lit + 1
    elseif before and before.p == at.p then
        return lit, lit - 1
    end
    return lit
end

--- How far the text is typed out, as the captions type it: the paragraph the voice is in and
--- the last byte of it shown, or nil for all of it. Nothing of the matched span before the
--- voice starts; up to and including the word being read while it speaks; everything once
--- it has finished, and for a clip with no length to time it by. A caption word the window
--- lacks types up to the last one before it that it has.
function Bridge.Cut(caption, map, span, paragraphs)
    if not caption.typewriter or not caption.progress or caption.progress >= 1 then
        return nil
    end
    local index = caption.speaking and caption.activeWord or 0
    while index > 0 and not map[index] do
        index = index - 1
    end
    if index == 0 then
        return span.first, 0
    end
    local at = map[index]
    return at.p, paragraphs[at.p].words[at.w].last
end

--- `text` with the words at `spans` (sorted by position) wrapped in `color`.
function Bridge.Wrap(text, spans, color)
    local parts, from = {}, 1
    for _, span in ipairs(spans) do
        table.insert(parts, string.sub(text, from, span.first - 1))
        table.insert(parts, color .. string.sub(text, span.first, span.last) .. "|r")
        from = span.last + 1
    end
    table.insert(parts, string.sub(text, from))
    return table.concat(parts)
end

--- The highlight for a paragraph's text colour: gold on dark text's light background is
--- unreadable, so dark text gets the red.
function Bridge.ColorFor(r, g, b)
    if (r or 1) * 0.299 + (g or 1) * 0.587 + (b or 1) * 0.114 < 0.5 then
        return ON_LIGHT
    end
    return ON_DARK
end

--------------------------------------------------------------------------------
-- Drawing it
--------------------------------------------------------------------------------

-- paragraphs: { fs, text (DialogueUI's), shown (what this file last set), words, color }.
-- clip, map and span: the caption last matched against them. lit/neighbor: the caption words
-- lit; cutP/cutByte: how far the text is typed out (Bridge.Cut). pending: the line about to be
-- read for the page just built, before it is queued: { words, untilTime, map, span }.
local state = { dirty = true }
-- Whether the player can give the words being read (Spoken:GetCaption): asked once, in Hook.
local canMark = false

-- A FontString set to "" may read back as nil.
local function Showing(fs)
    return fs:GetText() or ""
end

--- Put every paragraph's own text back. Only where it still shows what this file set:
--- DialogueUI may have reused the FontString for something else since.
local function Restore()
    for _, para in ipairs(state.paragraphs or {}) do
        if para.shown ~= para.text and Showing(para.fs) == para.shown then
            para.fs:SetText(para.text)
        end
        para.shown = para.text
    end
    state.lit, state.neighbor, state.cutP, state.cutByte = nil, nil, nil, nil
end

--- The text DialogueUI is showing now: its paragraphs, not their translations, not the
--- title or the objectives' heading (which carry no text-to-speech flag).
local function Collect()
    local paragraphs = {}
    for _, fs in DUIQuestFrame.fontStringPool:EnumerateActive() do
        if not fs.isTranslation and (fs.ttsFlag ~= nil or fs.isTranslation == false) then
            local text = fs:GetText()
            local words = type(text) == "string" and Spoken:SplitCaption(text)
            if words and table.getn(words) > 0 then
                table.insert(paragraphs, { fs = fs, text = text, shown = text, words = Bridge.MarkLinks(text, words),
                    color = Bridge.ColorFor(fs:GetTextColor()) })
            end
        end
    end
    return paragraphs
end

--- A page was built: drop what was matched against the last one. Kept gossip history is not
--- rebuilt, so its paragraphs are restored first.
local function Invalidate()
    Restore()
    state.paragraphs, state.clip, state.map, state.span, state.dirty = nil, nil, nil, nil, true
    state.scrolledTo = nil
end

local function ScrollIntoView(fs)
    local frame = DUIQuestFrame
    if not (frame.IsScrollable and frame:IsScrollable() and frame.ScrollTo and frame.ScrollFrame) then
        return
    end
    local scroll = frame.ScrollFrame
    local contentTop, top, bottom = frame.ContentFrame:GetTop(), fs:GetTop(), fs:GetBottom()
    if not (contentTop and top and bottom) then
        return
    end
    local from, to = contentTop - top, contentTop - bottom
    local view = scroll:GetHeight()
    local current = scroll.scrollTarget or scroll.value or 0
    if from >= current and to <= current + view then
        return
    end
    -- A little of what came before stays in view above it.
    frame:ScrollTo(math.max(0, math.min(scroll.range or 0, from - view * 0.2)))
end

local function Draw(map, span, lit, neighbor, cutP, cutByte)
    local spans = {}
    for _, index in ipairs({ lit, neighbor }) do
        local at = map[index]
        if at then
            spans[at.p] = spans[at.p] or {}
            table.insert(spans[at.p], state.paragraphs[at.p].words[at.w])
        end
    end
    for p, para in ipairs(state.paragraphs) do
        local want = para.text
        -- Typed out: the paragraphs the line covers, up to the voice. Those around them --
        -- earlier gossip, the objectives' list -- are not the line's and stay whole.
        if cutP and p >= span.first and p <= span.last then
            if p > cutP then
                want = ""
            elseif p == cutP then
                want = string.sub(para.text, 1, cutByte)
            end
        end
        if spans[p] then
            -- Only words already typed: the neighbour past the voice is not shown yet.
            local shown, kept = string.len(want), {}
            for _, word in ipairs(spans[p]) do
                if word.last <= shown then
                    table.insert(kept, word)
                end
            end
            table.sort(kept, function(a, b) return a.first < b.first end)
            want = Bridge.Wrap(want, kept, para.color)
        end
        if want ~= para.shown then
            if Showing(para.fs) ~= para.shown then
                -- DialogueUI changed it under us without a rebuild this file heard of.
                Invalidate()
                return
            end
            para.fs:SetText(want)
            para.shown = want
        end
    end
    state.lit, state.neighbor, state.cutP, state.cutByte = lit, neighbor, cutP, cutByte
    -- Keep the voice in view: the word lit, or else the paragraph being typed.
    local target = lit and map[lit] and map[lit].p or cutP
    if target and target ~= state.scrolledTo then
        state.scrolledTo = target
        if Config().AutoScroll then
            ScrollIntoView(state.paragraphs[target].fs)
        end
    end
end

local function Tick()
    if not Config().Captions then
        Restore()
        state.pending = nil
        return
    end
    if state.dirty then
        state.paragraphs, state.dirty = Collect(), false
        state.clip = nil
    end
    local caption = Spoken:GetCaption()
    local clip = caption and caption.clip
    -- This addon's lines only: a zone's or a book's never match DialogueUI's text anyway.
    if clip and clip.source == Player.source then
        if clip ~= state.clip then
            -- Put back and drawn again in this one call: nothing shows in between.
            Restore()
            state.clip, state.scrolledTo = clip, nil
            state.map, state.span = Bridge.Align(caption.words, state.paragraphs)
        end
    else
        state.clip, state.map = nil, nil
    end
    -- Neither Highlight Words nor Type Words Out on in Spoken's settings: DialogueUI's text
    -- as DialogueUI drew it.
    if state.map and (caption.highlight or caption.typewriter) then
        -- The line the page was waiting for is here.
        state.pending = nil
        local lit, neighbor
        if caption.highlight then
            lit, neighbor = Bridge.Pick(state.map, caption.speaking and caption.activeWord or nil)
        end
        local cutP, cutByte = Bridge.Cut(caption, state.map, state.span, state.paragraphs)
        if lit ~= state.lit or neighbor ~= state.neighbor or cutP ~= state.cutP or cutByte ~= state.cutByte then
            Draw(state.map, state.span, lit, neighbor, cutP, cutByte)
        end
        return
    end
    -- No line of this page's playing yet, but one is about to be queued for it: its words
    -- wait blank, as typed-out words do before the voice starts. Not behind another part's
    -- line -- a zone's lore, a book page -- which the quest's waits for in the queue.
    local pending = state.pending
    local otherPart = clip ~= nil and clip.source ~= Player.source
    if pending and not otherPart and GetTime() < pending.untilTime then
        if not pending.span then
            pending.map, pending.span = Bridge.Align(pending.words, state.paragraphs)
        end
        if pending.map then
            if state.lit or state.cutP ~= pending.span.first or state.cutByte ~= 0 then
                Draw(pending.map, pending.span, nil, nil, pending.span.first, 0)
            end
            return
        end
    end
    state.pending = nil
    Restore()
end

--- A page was just built. When Spoken Quests is about to read it and Spoken types words
--- out, remember the words its line will carry, so the first frame the page is drawn in
--- already has them blank (Tick, run at once by the hook in Hook).
function Bridge.Expect(handler)
    state.pending = nil
    local event = EVENTS[handler]
    if not (event and Config().Captions and Spoken.GetCaptionOptions and Addon.ExpectedLine) then
        return
    end
    local _, typewriter = Spoken:GetCaptionOptions()
    if not typewriter then
        return
    end
    local ok, text = pcall(Addon.ExpectedLine, Addon, event)
    local words = ok and type(text) == "string" and Spoken:SplitCaption(text)
    if words and table.getn(words) > 0 then
        state.pending = { words = words, untilTime = GetTime() + HOLD }
    end
end

--------------------------------------------------------------------------------
-- The player over the window
--------------------------------------------------------------------------------

local hosting = false

--- Put the player on DialogueUI's window while it is open and the setting is on; back on
--- UIParent otherwise.
function Bridge:UpdatePlayerHost()
    if not (_G.Spoken and Spoken.SetPlayerHost and self.driver) then
        return
    end
    local want = self.driver:IsVisible() and Config().ShowPlayer and true or false
    if want ~= hosting then
        hosting = want
        Spoken:SetPlayerHost(want and DUIQuestFrame or nil)
    end
end

--------------------------------------------------------------------------------
-- The Contribute button
--------------------------------------------------------------------------------

--- The dialog event of the page DialogueUI's window shows (EVENTS), or nil while it is closed
--- or when this file stood down. What the game's own quest and gossip frames say without
--- DialogueUI, which never shows them: Contribute.lua asks it to know what is on screen, and
--- UI/ContributeButton.lua to put its button on this window. `handler` is DialogueUI's name
--- for the page builder it last ran; nil until the first dialog, so not part of Recognised.
function Bridge:Page()
    local frame = self.driver and _G.DUIQuestFrame
    if frame and frame:IsShown() then
        return EVENTS[frame.handler]
    end
end

--- The Contribute button follows the window: it opens, closes and changes page with no
--- event the button hears in time, since DialogueUI builds the page before showing it.
local function RefreshContribute()
    local button = rawget(VoiceOver, "ContributeButton")
    if button and button.Refresh then
        button:Refresh()
    end
end

--- Spoken's copy box, which a click on the button opens, over the window while it is open:
--- it is a child of UIParent, which DialogueUI hides.
local function HostContributeBox(host)
    if _G.Spoken and Spoken.SetContributeHost then
        Spoken:SetContributeHost(host)
    end
end

--------------------------------------------------------------------------------
-- DialogueUI's Play button
--------------------------------------------------------------------------------

-- The line DialogueUI last asked about, and the event it stands for. DialogueUI asks as the
-- page opens; Play and Stop then act on that line.
local line, lineEvent
-- How long DialogueUI's autoplay waits before it plays: DialogueUI's floor, so it comes
-- after this addon's.
local AUTOPLAY_DELAY = 0.5
-- When DialogueUI's autoplay will call playFile. It asks the delay (getAutoPlayDelay) just
-- before it waits, and a click on its button never does, which is how the two are told apart.
local autoplayAt

--------------------------------------------------------------------------------
-- Autoplay, with DialogueUI's Auto Play
--------------------------------------------------------------------------------

-- DialogueUI's Auto Play, from its saved settings: what its settings and a right-click on its
-- Text To Speech button change.
local function TheirAutoplay()
    local db = _G.DialogueUI_DB
    return type(db) == "table" and db.TTSAutoPlay == true
end

--- Whether DialogueUI's Text To Speech button plays this addon's lines just now: DialogueUI's
--- Text To Speech on (its saved setting) and running -- not just turned on by this file and
--- waiting for a reload -- and Use DialogueUI's Play Button on here. Its Auto Play then has a
--- say in this addon's, as the DialogueUI page's Read Automatically chooses.
function Bridge:AutoplayLinked()
    local db = _G.DialogueUI_DB
    return self.provider == true and Config().PlayButton == true and type(db) == "table"
        and db.TTSEnabled == true and not self.ttsPending
end

--- DialogueUI's Text To Speech, on wherever Use DialogueUI's Play Button and Turn On
--- DialogueUI's Text To Speech are: its button is the one that plays this addon's lines, and
--- DialogueUI has it off by default. Turned on in DialogueUI's saved settings, which DialogueUI
--- reads at its next load: it loads them before this addon runs and has no public way to
--- change them, so the player is asked once to reload. Turned off in DialogueUI, it is on again
--- at the next login, unless Turn On DialogueUI's Text To Speech is off here.
function Bridge:EnsureTextToSpeech()
    local db = _G.DialogueUI_DB
    if not (self.provider == true and Config().PlayButton and Config().EnableTTS and type(db) == "table")
        or db.TTSEnabled == true then
        return false
    end
    db.TTSEnabled = true
    self.ttsPending = true
    print("|cFF00CCFFSpoken Quests:|r " .. L.OPT_DUI_TTS_TURNED_ON)
    return true
end

--- Whether DialogueUI's Auto Play decides this addon's autoplay, Read Automatically waiting.
function Bridge:FollowsAutoplay()
    return self:AutoplayLinked() and Config().Autoplay ~= "sync"
end

-- DialogueUI's Auto Play as Keep in Sync last saw it, to tell which of the two changed.
local seenAutoplay

--- Set DialogueUI's Auto Play: by a right-click on its Text To Speech button, which is how
--- DialogueUI changes it while it runs (it keeps a copy that only its own setter updates);
--- written into its saved settings where there is no button to click.
local function SetTheirAutoplay(on)
    if TheirAutoplay() == on then
        return
    end
    local button = _G.DUIQuestFrame and DUIQuestFrame.TTSButton
    if type(button) == "table" and button.Click then
        pcall(button.Click, button, "RightButton")
    end
    if TheirAutoplay() ~= on then
        DialogueUI_DB.TTSAutoPlay = on
    end
end

--- Keep in Sync: whichever of Read Automatically and DialogueUI's Auto Play changed since
--- last seen, the other follows. Seen for the first time, DialogueUI's follows this addon's.
function Bridge:SyncAutoplay()
    if not (self:AutoplayLinked() and Config().Autoplay == "sync") then
        seenAutoplay = nil
        return
    end
    local audio = Addon.db.profile.Audio
    local theirs, ours = TheirAutoplay(), audio.Autoplay ~= false
    if seenAutoplay ~= nil and theirs ~= seenAutoplay then
        audio.Autoplay = theirs
    elseif theirs ~= ours then
        SetTheirAutoplay(ours)
        theirs = TheirAutoplay()
    end
    seenAutoplay = theirs
end

--- This addon's autoplay as DialogueUI has it, for Addon:IsAutoplayOn: DialogueUI's Auto Play
--- while followed; nil where Read Automatically decides -- kept the same as DialogueUI's
--- first in Keep in Sync -- and always without DialogueUI's Text To Speech button.
function Bridge:AutoplayFor()
    if not self:AutoplayLinked() then
        seenAutoplay = nil
        return nil
    end
    if Config().Autoplay == "sync" then
        self:SyncAutoplay()
        return nil
    end
    return TheirAutoplay()
end

--- Whether `line` is the clip at the head of the player's queue: speaking, or paused on it.
local function IsSpeaking(soundData)
    local head = Spoken.GetCurrent and Spoken:GetCurrent()
    return head ~= nil and head.fileName == soundData.fileName
end

local provider = {
    name = "Spoken Quests",
    -- DialogueUI hears the client's event before this addon's recorder does, so the event is
    -- taken from what DialogueUI says it is showing, never from GetVisibleDialogueEvent.
    doesFileExist = function(interactionType, _, page)
        line, lineEvent = nil, nil
        if not Config().PlayButton then
            return false
        end
        local event = interactionType == "gossip" and "GOSSIP_SHOW" or QUEST_EVENTS[page]
        if not event then
            return false
        end
        local ok, found = pcall(Addon.GetVisibleLine, Addon, event)
        if ok and found then
            line, lineEvent = found, event
            return true
        end
        return false
    end,
    -- Not again when it is already queued: with autoplay on, DialogueUI's own autoplay would
    -- read every line twice.
    playFile = function()
        -- DialogueUI's autoplay rather than its button: this addon's own autoplay reads the
        -- line or not (Addon:IsAutoplayOn, which follows or syncs DialogueUI's Auto Play), so
        -- DialogueUI's copy of that setting, which can lag, never reads it too.
        local now = GetTime()
        if autoplayAt and now >= autoplayAt - 0.1 and now <= autoplayAt + 0.5 then
            autoplayAt = nil
            if Bridge:AutoplayLinked() then
                return
            end
        end
        -- Now, whatever else is speaking: it is skipped (Player:PlayPreparedNow). Already
        -- speaking, nothing to do; queued behind something else, brought to the front.
        if line and not IsSpeaking(line) then
            Player.playNow = true
            Addon:InvokeQuestHandler(lineEvent, "DialogueUI Play button", true)
            Player.playNow = nil
        end
    end,
    -- Only while the window is up, i.e. its Stop button. DialogueUI also calls this as the
    -- window closes -- accepting a quest closes it -- under its own "TTS Auto Stop", which is
    -- on by default even with its text-to-speech off. Whether closing the dialog stops the
    -- line is this addon's "Stop When Window Closes" to decide, and it defaults to
    -- letting the line finish.
    stopPlaying = function()
        if not DUIQuestFrame:IsShown() then
            return
        end
        local clip = line and Player:QueuedClipFor(line)
        if clip then
            Player:Remove(clip)
        end
    end,
    -- Speaking, not just queued: DialogueUI's button stops a line that plays and plays one that
    -- does not, and a line waiting behind another is one to bring forward, not to drop.
    isPlaying = function()
        return line ~= nil and IsSpeaking(line)
    end,
    -- DialogueUI's floor, so its autoplay comes after this addon's.
    getAutoPlayDelay = function()
        autoplayAt = GetTime() + AUTOPLAY_DELAY
        return AUTOPLAY_DELAY
    end,
}

--------------------------------------------------------------------------------
-- Waiting for the window
--------------------------------------------------------------------------------

-- The read waiting for DialogueUI's window: { event, run, untilTime }.
local waiting

--- Whether DialogueUI's window shows `event`'s page in full: open on that page, its intro
--- played (DialogueUI fades or unfolds the window in) and its text faded in.
local function InFullView(event)
    local frame = _G.DUIQuestFrame
    if not (frame and frame:IsShown() and EVENTS[frame.handler] == event) then
        return false
    end
    local content = frame.ContentFrame
    return (frame:GetAlpha() or 1) >= 0.99 and not (content and (content:GetAlpha() or 1) < 0.99)
end

--- An automatic read of `event`, held until DialogueUI's window shows its page in full, so the
--- voice starts with the words on screen rather than while the window is still appearing.
--- `run` reads it then, or after WAIT_LIMIT. False -- read at once -- where DialogueUI is not
--- showing this page at all: not hooked, closed (it passed this dialog to the game, a muted
--- quest, an instance), or on another page.
function Bridge:Defer(event, run)
    if not self.driver or self.reading then
        return false
    end
    local frame = _G.DUIQuestFrame
    if not (frame and frame:IsShown() and EVENTS[frame.handler] == event) or InFullView(event) then
        return false
    end
    waiting = { event = event, run = run, untilTime = GetTime() + WAIT_LIMIT }
    return true
end

--- Read what was waiting, once its page is in full view or it has waited long enough. Run by
--- the driver, which ticks only while the window is open.
local function Release()
    if not waiting or not (InFullView(waiting.event) or GetTime() >= waiting.untilTime) then
        return
    end
    local run = waiting.run
    waiting = nil
    Bridge.reading = true
    local ok, err = pcall(run)
    Bridge.reading = nil
    if not ok then
        Debug:Record("dialogueui-wait-error", tostring(err))
    end
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

function Bridge:Hook()
    if self.driver then
        return
    end
    local problem = self:Problem()
    if problem then
        self.status = problem
        return
    end
    local frame = DUIQuestFrame
    -- Asked once: the player's API cannot change within a session.
    canMark = not self:Problem("Captions")
    for _, name in ipairs(HANDLERS) do
        local handler = name
        hooksecurefunc(frame, handler, function()
            Invalidate()
            -- At once rather than on the next tick: the page DialogueUI just built is drawn
            -- at the end of this frame, and must already be as it should look.
            if canMark then
                Bridge.Expect(handler)
                Tick()
            end
            RefreshContribute()
        end)
    end

    -- A child of the window, so it runs only while the window is up. DUIQuestFrame's own
    -- OnHide is no use: DialogueUI sets it with SetScript, replacing any hook.
    local driver = CreateFrame("Frame", nil, frame)
    local elapsedSince = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        Release()
        elapsedSince = elapsedSince + elapsed
        if elapsedSince >= TICK and canMark then
            elapsedSince = 0
            Tick()
        end
    end)
    driver:SetScript("OnShow", function()
        self:UpdatePlayerHost()
        HostContributeBox(frame)
        RefreshContribute()
    end)
    driver:SetScript("OnHide", function()
        Restore()
        state.pending = nil
        -- Closed before it showed in full: the player walked on, and the line is not read.
        waiting = nil
        self:UpdatePlayerHost()
        HostContributeBox(nil)
        RefreshContribute()
    end)
    self.driver = driver

    -- One provider per session, and DialogueUI warns if another voiceover addon has it.
    -- Registered even with the setting off, so turning it on needs no reload.
    if not self:Problem("PlayButton") then
        DialogueUIAPI.SetVOProvider(provider)
        self.provider = true
        self:EnsureTextToSpeech()
    end
    self.ensureWas = (Config().PlayButton and Config().EnableTTS) and true or false
    self.status = "hooked"
end

function Bridge:Setup()
    if not IsLoaded("DialogueUI") then
        self.status = L.OPT_DUI_MISSING
        return
    end
    -- After every addon has loaded: DialogueUI builds the page methods with its frame.
    if IsLoggedIn and IsLoggedIn() then
        self:Hook()
        return
    end
    local login = CreateFrame("Frame")
    login:RegisterEvent("PLAYER_LOGIN")
    login:SetScript("OnEvent", function(waiter)
        waiter:UnregisterEvent("PLAYER_LOGIN")
        local ok, err = pcall(self.Hook, self)
        if not ok then
            self.status = "error: " .. tostring(err)
            Debug:Record("dialogueui-error", tostring(err))
        end
    end)
end

--- A setting changed on the panel.
function Bridge:Refresh()
    if not Config().Captions then
        Restore()
    end
    -- Use DialogueUI's Play Button or Turn On DialogueUI's Text To Speech just turned on: the
    -- button has to be there. Only then, so changing another setting never turns back on what
    -- the player turned off in DialogueUI.
    local ensure = (Config().PlayButton and Config().EnableTTS) and true or false
    if ensure and not self.ensureWas then
        self:EnsureTextToSpeech()
    end
    self.ensureWas = ensure
    self:UpdatePlayerHost()
end

--- One line for /spq diagnostics.
function Bridge:Describe()
    return format("DialogueUI: %s; words=%s scroll=%s player=%s play=%s autoplay=%s%s", tostring(self.status),
        tostring(Config().Captions), tostring(Config().AutoScroll), tostring(Config().ShowPlayer),
        tostring(Config().PlayButton), tostring(Config().Autoplay),
        self:AutoplayLinked() and " (linked)" or "")
end
