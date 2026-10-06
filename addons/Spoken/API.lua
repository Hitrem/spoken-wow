setfenv(1, SpokenEnv)

-- The public surface. Everything a feature addon may rely on is defined in this file;
-- nothing else on `Spoken` is a contract, and nothing here writes anywhere but `Spoken`.
--
-- API_VERSION moves only on a breaking change. A feature addon's entire hard requirement
-- is `_G.Spoken and Spoken:IsCompatible(1)`. A copy bundled into a legacy-client zip may
-- lag the one an addon manager installs, so this is what lets the two disagree safely.
Spoken.API_VERSION = 1
Spoken.ADDON_VERSION = AddonVersion

---@param required number The API_VERSION the caller was written against.
function Spoken:IsCompatible(required)
    return type(required) == "number" and required <= self.API_VERSION
end

--------------------------------------------------------------------------------
-- Sources: how a feature addon joins the player. See Sources.lua for the info shape.
--------------------------------------------------------------------------------

---@param key string  "quests" | "zones" | "books"
---@param info SpokenSourceInfo
---@return table source  Carries Enqueue, PlayNow, Remove, StopAll, AddGate, RecheckGates, Retry,
---                      CanPlay, SetQueueLimit and SetInterClipGap.
function Spoken:RegisterSource(key, info)
    return Sources:Register(key, info)
end

function Spoken:GetSource(key)
    return Sources:Get(key)
end

--- Iterates `key, source` in menu order.
function Spoken:IterateSources()
    return Sources:Iterate()
end

--------------------------------------------------------------------------------
-- Clips and presentation
--------------------------------------------------------------------------------
--
-- A clip is what a source enqueues. The caller owns the file and the duration; the player
-- never resolves a path.
--
--   clip = {
--     key      = "q:33:accept",               -- caller-unique; the dedup key
--     path     = [[Interface\AddOns\...\x.ogg]],
--     length   = 3.4,                         -- seconds; the client cannot report this
--     delay    = nil,                         -- silence before; only 2.4.3/3.3.5 set it
--     priority = "normal" | "low",            -- low yields at the door; gossip is low
--     present  = {
--       header   = "Eagan Peltskinner",       -- NPC name | zone name | book title
--       label    = "Wolves Across the Border",-- quest title | subzone | page label
--       transcript = "Full dialogue text",   -- optional; falls back to clip.text
--       bullet   = "quest-accept",            -- a RegisterBullet id
--       tint     = { r, g, b },               -- optional row tint
--       portrait = { kind = "model", creatureID = 196 }
--                | { kind = "texture", texture = [[...]], texCoord = { l, r, t, b } }
--                | { kind = "none" },
--       actions  = { { id, text, tooltip, visible, onClick, create }, ... },
--     },
--     addedCallback = fun(clip), startCallback = fun(clip),
--     stopCallback  = fun(clip, finishedPlaying),
--   }
--
-- The player sets id, handle, source and nextSoundTimer; a caller never does.

--- A row bullet, registered once by a feature addon so SpokenBooks needs no change to
--- the player to have one of its own.
--- Declare an action switchable, and what the player's settings should call it. Both
--- shipped addons declare their Report action, so one setting covers whichever is speaking.
---@param id string the action id, as it appears in a clip's presentation
---@param label string what to call it, e.g. "Report"
function Spoken:RegisterOptionalAction(id, label)
    return Actions:RegisterOptional(id, label)
end

function Spoken:RegisterBullet(id, texture, size)
    Bullets[id] = { texture = texture, size = size }
end

function Spoken:GetBullet(id)
    return Bullets[id]
end

--- A portrait renderer: { Acquire(portrait, parent) -> frame, Update(frame, clip) -> bool,
--- Release(frame) }. Acquire/Release exist because 1.12 and 2.4.3 pool DressUpModel
--- frames, and the pooling has to live somewhere. "texture", "model" and "none" ship with
--- the player.
function Spoken:RegisterPortraitRenderer(kind, renderer)
    Renderers[kind] = renderer
end

function Spoken:GetPortraitRenderer(kind)
    return Renderers[kind]
end

--- Ask the client about a creature whose portrait may soon be drawn, so the minimal player
--- has its face by then rather than the book while the client fetches it. A no-op in the
--- other layout, which draws a 3D model and needs nothing ahead of time.
function Spoken:PrimePortrait(creatureID)
    if MinimalPlayer and MinimalPlayer:IsEnabled() then StaticPortrait:Prime(creatureID) end
end

--------------------------------------------------------------------------------
-- Contributions: sending text the corpus does not have
--------------------------------------------------------------------------------
--
-- Additive, so API_VERSION does not move. A feature addon guards on the field rather than the
-- version: `if Spoken.Contribute and Spoken.ShowContribution then`. A legacy-client zip may
-- bundle a player older than the addon beside it, and that player should mean no contribute
-- button, not an error.
--
-- The same goes for the setting that hides those buttons: guard on the method, and an older
-- player without it simply means the buttons are shown.

--- Whether the player turned every Contribute button off in the Spoken settings.
--- A feature addon asks this in its gap check, and re-asks on CONTRIBUTE_SETTINGS_CHANGED.
function Spoken:AreContributeButtonsHidden()
    return Addon.db and Addon.db.profile.Contribute.HideButtons and true or false
end

--------------------------------------------------------------------------------
-- The frame, the minimap button, the settings
--------------------------------------------------------------------------------

--- The player window, for a feature addon that must anchor something to it.
function Spoken:GetPlayerFrame()
    if MinimalPlayer:IsEnabled() then return MinimalPlayer.frame end
    return PlayerFrame.frame
end

--- The Settings category, so a feature addon can nest its panel under it with
--- Settings.RegisterCanvasLayoutSubcategory. Nil on clients without the Settings API.
function Spoken:GetSettingsCategory()
    return Options.category
end

function Spoken:OpenSettings()
    Options:Open()
end

--- Re-read the speaking clip's presentation -- after a setting changed an action's
--- label, say. Cheap; the frame rebuilds from the queue every time anyway.
function Spoken:RefreshPlayer()
    PlayerFrame:Update()
end

--- A feature addon's settings page, shown under Spoken's own in the game's settings as `name`,
--- listed in `order` (Quests 1, Books 2, Zones 3). Pass the page's SpokenLayout and its
--- scroller to make its rows searchable from Home. Returns a table whose `category` is
--- filled in once the page is registered, for Settings.OpenToCategory; nil where the client
--- cannot nest pages, in which case the addon registers a top-level page as before.
function Spoken:AddSettingsPage(panel, name, order, layout, scroller)
    return Options:AddPage(panel, name, order, layout, scroller)
end

--- Whether a part of Spoken is switched on in the settings (Sources:IsTurnedOff), for the
--- switch each feature addon puts at the top of its own page. `key` is its source key.
function Spoken:IsPartOn(key)
    return not Sources:IsTurnedOff(key)
end

--- How a part stands, as a state ("ok", "warn", "off") and the words for it: not installed,
--- switched off, or how many voice packs it found. For the line at the top of its own page.
function Spoken:PartStatus(key)
    return Options:PartStatus(key)
end

--- A module's voice packs, as its card shows them: how many of them it has, "Voice Pack ... 2/4".
--- Returns a kind, the words and the value.
function Spoken:PartVoice(key)
    return Options:PartVoice(key)
end

--- How Spoken's settings are laid out: "pages", each page an entry nested under Spoken in the
--- game's settings list, on a client with the settings canvas; nil without one.
function Spoken:SettingsStyle()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return nil end
    return "pages"
end

-- Each module's voice pack in each language but English, by its store page under publishers/:
-- the CurseForge project where it has one, its GitHub releases where it has not. English's packs
-- are each module's own to list. tests/lua/packs_test.lua keeps this in step with the pages.
local CURSEFORGE = "https://www.curseforge.com/wow/addons/"
local RELEASES = "https://github.com/rusty-key/spoken-wow/releases?q="
local PACK_FOLDERS = { quests = "SpokenQuestsAudio", zones = "SpokenZonesAudio", books = "SpokenBooksAudio" }
local PACK_PAGES = {
    quests = { deDE = "spoken-quests-audio-dede", esES = "spoken-quests-audio-eses", esMX = "spoken-quests-audio-esmx",
        frFR = "spoken-quests-audio-frfr", itIT = { github = "quests-audio-itIT" }, koKR = "spoken-quests-audio-kokr",
        ptBR = "spoken-quests-audio-ptbr", ruRU = "spoken-quests-audio-ruru" },
    zones = { deDE = "spoken-zones-audio-dede", esES = "spoken-zones-audio-eses", esMX = "spoken-zones-audio-esmx",
        frFR = "spoken-zones-audio-frfr", koKR = "spoken-zones-audio-kokr", ptBR = "spoken-zones-audio-ptbr",
        ruRU = "spoken-zones-audio-ruru", zhCN = "spoken-zones-audio-zhcn", zhTW = "spoken-zones-audio-zhtw" },
    books = { deDE = "spoken-books-audio-dede", esES = "spoken-books-audio-eses", esMX = "spoken-books-audio-esmx",
        frFR = "spoken-books-audio-frfr", koKR = "spoken-books-audio-kokr", ptBR = "spoken-books-audio-ptbr",
        ruRU = "spoken-books-audio-ruru", zhCN = "spoken-books-audio-zhcn", zhTW = "spoken-books-audio-zhtw" },
}

--- The voice pack `module` ("quests", "zones" or "books") has in `lang`, English's aside: the folder
--- it installs as and the address to get it, or nil where that language has none.
function Spoken:VoicePack(module, lang)
    local page = PACK_PAGES[module] and PACK_PAGES[module][lang]
    if not page then return nil end
    local url = type(page) == "table" and (RELEASES .. page.github) or (CURSEFORGE .. page)
    return PACK_FOLDERS[module] .. "_" .. lang, url
end

-- Zone icons by uiMapID, copied into Textures/Zones so every client has them. A city takes its
-- zone's icon, Teldrassil takes Darnassus's, and a map not listed takes its parent's.
local ZONE_ART = [[Interface\AddOns\Spoken\Textures\Zones\]]
local ZONE_ICONS = {
    [947] = "Azeroth", [1414] = "Kalimdor", [1415] = "EasternKingdoms",
    [1411] = "Durotar", [1412] = "Mulgore", [1413] = "Barrens", [1416] = "AlteracMountains",
    [1417] = "ArathiHighlands", [1418] = "Badlands", [1419] = "BlastedLands", [1420] = "TirisfalGlades",
    [1421] = "Silverpine", [1422] = "WesternPlaguelands", [1423] = "EasternPlaguelands",
    [1424] = "HillsbradFoothills", [1425] = "Hinterlands", [1426] = "DunMorogh", [1427] = "SearingGorge",
    [1428] = "BurningSteppes", [1429] = "ElwynnForest", [1430] = "DeadwindPass", [1431] = "Duskwood",
    [1432] = "LochModan", [1433] = "RedridgeMountains", [1434] = "Stranglethorn", [1435] = "SwampOfSorrows",
    [1436] = "Westfall", [1437] = "Wetlands", [1439] = "Darkshore", [1440] = "Ashenvale",
    [1441] = "ThousandNeedles", [1442] = "Stonetalon", [1443] = "Desolace", [1444] = "Feralas",
    [1445] = "DustwallowMarsh", [1446] = "Tanaris", [1447] = "Azshara", [1448] = "Felwood",
    [1449] = "UngoroCrater", [1451] = "Silithus", [1452] = "Winterspring", [1438] = "Teldrassil",
    [2482] = "MountHyjal",
    [1453] = "ElwynnForest", [1454] = "Durotar", [1455] = "DunMorogh", [1456] = "Mulgore",
    [1457] = "Teldrassil", [1458] = "TirisfalGlades",
    -- Forever's own zones, drawn for Spoken.
    [2521] = "ZephrasIsle", [2524] = "DarkspearIslands", [2548] = "Riverglades", [2652] = "Shendralas",
}
-- Trims the icons' bevelled border, as the game does in a round frame. The globe needs none.
local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }
local WHOLE = { 0, 1, 0, 1 }
Spoken.ZONE_ICONS = ZONE_ICONS

--- The icon for `mapID` or its nearest ancestor that has one, with its crop.
function Spoken:ZoneIcon(mapID)
    local depth = 0
    while mapID and depth < 6 do
        local icon = ZONE_ICONS[mapID]
        if icon then return ZONE_ART .. icon, icon == "Azeroth" and WHOLE or ICON_CROP end
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        mapID = info and info.parentMapID
        depth = depth + 1
    end
    return nil
end

-- C_Container where the client has it, else the old bag functions.
local function BagSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end
local function SlotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.iconFileID, info.hyperlink end
        return nil
    end
    if GetContainerItemInfo then
        local texture, _, _, _, _, _, link = GetContainerItemInfo(bag, slot)
        return texture, link
    end
end
local function SlotQuest(bag, slot)
    if C_Container and C_Container.GetContainerItemQuestInfo then
        local info = C_Container.GetContainerItemQuestInfo(bag, slot)
        return info and info.questID
    end
    if GetContainerItemQuestInfo then
        local _, questID = GetContainerItemQuestInfo(bag, slot)
        return questID
    end
end
local function BagIcon(test)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, BagSlots(bag) do
            if test(bag, slot) then
                local icon = SlotItem(bag, slot)
                if icon then return icon, ICON_CROP end
            end
        end
    end
    return nil
end

--- The icon of the bag item that starts `questID`, with its crop.
function Spoken:QuestItemIcon(questID)
    if not questID then return nil end
    return BagIcon(function(bag, slot) return SlotQuest(bag, slot) == questID end)
end

--- The icon of the bag item named `name`, with its crop.
function Spoken:BagItemIcon(name)
    if not name or name == "" then return nil end
    local bracketed = "[" .. name .. "]"
    return BagIcon(function(bag, slot)
        local _, link = SlotItem(bag, slot)
        return link ~= nil and string.find(link, bracketed, 1, true) ~= nil
    end)
end

--- The voice language and the fallback the player chose for every module, as stored: "auto"
--- or a language code, and a language code or "none". Either is nil while the player has not
--- chosen it here, and the module then keeps its own.
function Spoken:GetLanguageChoice()
    local language = Addon.db and Addon.db.profile.Language
    if not language then return nil, nil end
    return language.Voice, language.Fallback
end

function Spoken:SetPartOn(key, on)
    Sources:SetTurnedOff(key, not on)
    -- Home lists the same switch.
    Options:UpdateRows()
end

--- A button on the player's panel that opens a feature addon's own settings, for the
--- addons whose panel cannot be nested.
function Spoken:AddSettingsLink(text, onClick)
    Options:AddLink(text, onClick)
end

--- Menu entries for the one minimap button. entry = { id, text, icon, order, onClick,
--- tooltip, visible }.
Spoken.Minimap = {}
function Spoken.Minimap:AddEntry(sourceKey, entry)
    Minimap:AddEntry(sourceKey, entry)
end
function Spoken.Minimap:RemoveEntry(sourceKey, id)
    Minimap:RemoveEntry(sourceKey, id)
end

--------------------------------------------------------------------------------
-- The queue, player-wide. Source-scoped operations live on the source.
--------------------------------------------------------------------------------

--- The head: speaking, paused, or held by a gate. Queue rows read this.
function Spoken:GetCurrent()
    return SoundQueue:GetCurrentSound()
end

--- The head only if it is speaking or paused mid-clip. Controls read this: a held clip
--- sits at the head making no sound, and offering Pause over silence lies.
function Spoken:GetNowPlaying()
    return SoundQueue:GetNowPlaying()
end

--- A shallow copy.
function Spoken:GetQueue()
    return SoundQueue:GetQueue()
end

function Spoken:GetQueueSize()
    return SoundQueue:GetQueueSize()
end

--- Excludes the speaking head.
function Spoken:GetWaitingCount()
    return SoundQueue:GetWaitingCount()
end

function Spoken:IsPlaying(clip)
    return SoundQueue:IsPlaying(clip)
end

function Spoken:IsPaused()
    return SoundQueue:IsPaused()
end

function Spoken:GetHeldReason(clip)
    return SoundQueue:GetHeldReason(clip)
end

--- Pause is stop, and resume replays from the start: the client has no seek.
function Spoken:Pause()
    return SoundQueue:PauseQueue()
end

function Spoken:Resume()
    return SoundQueue:ResumeQueue()
end

function Spoken:TogglePause()
    return SoundQueue:TogglePauseQueue()
end

--- The player's round button, the same one its subtitle shows, for a feature addon's own
--- window: `kind` "play" (Play's glyph; `button:SetPlaying(on)` shows Pause while a line
--- speaks), "report" (the bug), or "icon" (the texture `icon`, cut round). Anchor it and give
--- it OnClick yourself.
function Spoken:CreateRoundButton(parent, kind, name, icon)
    return Actions.NewRound(parent, kind, name, icon)
end

--- End the head; the backlog runs.
function Spoken:Skip()
    return SoundQueue:Skip()
end

--- Everything, every source, and the paused flag with it.
function Spoken:StopAll()
    SoundQueue:RemoveAllSoundsFromQueue()
end

--- A gate that applies to every source: fn(clip) -> reason | nil.
--- Switch a channel off on a source's behalf, e.g. Dialog while a quest line speaks.
--- Unlike a channel the user disabled, clips on it are still admitted, and the mute is
--- lifted before one plays.
function Spoken:MuteChannel(channel, muted)
    SoundUtils:MuteChannel(channel, muted)
end

--- The source is about to queue a line: silence the game's NPC dialogue now rather than
--- when the line starts, so an NPC's greeting is never heard instead of being cut short.
--- Honours the player's "mute game dialogue" setting, and lifts itself if nothing comes.
function Spoken:MuteGameDialogueAhead(source)
    SoundQueue:MuteGameDialogueAhead(source:GetChannel())
end

function Spoken:AddGate(fn)
    SoundQueue:AddGate(fn)
end

--------------------------------------------------------------------------------
-- Callbacks
--------------------------------------------------------------------------------
--
--   AUDIO_CHANGED      ()                  coarse; after every mutation
--   CLIP_QUEUED        (clip)
--   CLIP_STARTED       (clip)
--   CLIP_STOPPED       (clip, finishedPlaying)
--   CLIP_DROPPED       (clip, reason)      queue-limit | outranked | missing | an admit reason
--   QUEUE_EMPTY        ()
--   SOURCE_REGISTERED  (source)
--   CONTRIBUTE_SETTINGS_CHANGED ()          the hide-Contribute-buttons setting was toggled

function Spoken:RegisterCallback(event, fn)
    return Callbacks:Register(event, fn)
end

function Spoken:UnregisterCallback(handle)
    Callbacks:Unregister(handle)
end

--------------------------------------------------------------------------------
-- Packs
--------------------------------------------------------------------------------
--
-- A registry convention, not a resolver: each feature addon owns discovering and
-- resolving its own packs, and the player only ever sees a clip's path. This gives new
-- packs one place to register and one shared utility for the TOC-key scan.

Spoken.Packs = { bySource = {} }

function Spoken.Packs:Register(sourceKey, folderName, pack)
    self.bySource[sourceKey] = self.bySource[sourceKey] or {}
    self.bySource[sourceKey][folderName] = pack
end

--- Unsorted; the source ranks them.
function Spoken.Packs:Get(sourceKey)
    local list = {}
    for _, pack in pairs(self.bySource[sourceKey] or {}) do
        table.insert(list, pack)
    end
    return list
end

--- Every installed addon whose TOC carries `tocKey`, as an iterator over
--- `index, folderName, value`. The reusable half of the quests addon's DataModules
--- scan, wrapping the GetAddOnMetadata / C_AddOns split.
function Spoken:EnumerateAddonsWithKey(tocKey)
    local numAddons = C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns() or GetNumAddOns()
    local getInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
    local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local i = 0
    return function()
        while i < numAddons do
            i = i + 1
            local value = getMeta(i, tocKey)
            if value and value ~= "" then
                local folder = getInfo(i)
                return i, folder, value
            end
        end
    end
end
