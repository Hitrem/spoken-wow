setfenv(1, VoiceOver)

-- The addon's face in the interface settings: one canvas panel of sections, laid out by
-- UI/Layout.lua, the file every Spoken addon carries a copy of so the three panels read
-- alike.
--
-- The AceConfig table is not replaced. It still backs every `/spq` command, and it still
-- fills the window OpenConfigWindow shows -- which is where profiles and the sound-pack
-- manager live, both of them AceGUI's to draw. What changed is that the settings a player
-- actually changes are sections on one panel rather than entries in a tree.
--
-- Absent on the three private-server clients, which have no Settings API at all. There the
-- window and the slash commands are the whole interface, as they have always been.

SettingsPanel = {}

local INDENT = 20
local panel, category

-- The enum is stored as a number and read as a name. Ordered, because a cycle button
-- steps through them in the order the list is written.
local GOSSIP_ORDER = { "Always", "OncePerQuestNPC", "OncePerNPC", "Never" }
local GOSSIP_LABELS = {
    Always = L.OPT_GREETING_LABEL_ALWAYS,
    OncePerQuestNPC = L.OPT_GREETING_LABEL_ONCE_QUEST,
    OncePerNPC = L.OPT_GREETING_LABEL_ONCE_NPC,
    Never = L.OPT_GREETING_LABEL_NEVER,
}

local function GossipName()
    return Enums.GossipFrequency:GetName(Addon.db.profile.Audio.GossipFrequency) or "Always"
end

function SettingsPanel:Setup()
    if panel or not (Settings and Settings.RegisterCanvasLayoutCategory) then
        return
    end
    panel = CreateFrame("Frame", "SpokenQuestsOptionsPanel", UIParent)
    panel.name = "Spoken Quests"

    -- The settings canvas is a fixed size and neither scrolls nor clips what overflows
    -- it, so a panel with more rows than fit draws them over the game world.
    local scroller = SpokenLayout.Scroll(panel)
    local content = scroller.child

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", INDENT, -16)
    title:SetText("Spoken Quests")

    local layout = SpokenLayout.New(content, INDENT, -42)
    panel.layout = layout
    local audio = function() return Addon.db.profile.Audio end

    layout:Note(L.OPT_PANEL_NOTE, 460, 32)

    layout:Section(L.OPT_SECTION_DIALOGUE)
    local greetings
    -- Greyed out with autoplay off: the frequency only decides which greetings autoplay
    -- reads, and a live control that does nothing reads as broken.
    local function SyncGreetings()
        if not greetings then
            return
        end
        local on = Addon:IsAutoplayOn()
        if greetings:GetObjectType() == "Frame" and UIDropDownMenu_EnableDropDown then
            (on and UIDropDownMenu_EnableDropDown or UIDropDownMenu_DisableDropDown)(greetings)
        elseif greetings.Enable then
            -- The Cycle button Layout:Dropdown falls back to where there is no dropdown API.
            if on then greetings:Enable() else greetings:Disable() end
        end
        local shade = on and 1 or 0.5
        if greetings.layoutLabel then
            greetings.layoutLabel:SetTextColor(shade, shade, shade)
        end
    end
    layout:Checkbox(L.OPT_PANEL_AUTOPLAY,
        L.OPT_PANEL_AUTOPLAY_TIP,
        function() return Addon:IsAutoplayOn() end,
        function(value) Addon:SetAutoplay(value) end,
        SyncGreetings)
    layout:Indent()
    greetings = layout:Dropdown(L.OPT_PANEL_GREETINGS, L.OPT_PANEL_GREETINGS_TIP,
        GOSSIP_ORDER,
        GossipName,
        function(name)
            Addon.db.profile.Audio.GossipFrequency = Enums.GossipFrequency[name]
        end,
        nil,
        function(name) return GOSSIP_LABELS[name] or name end)
    layout:Outdent()
    SyncGreetings()
    if greetings.HookScript then
        greetings:HookScript("OnShow", SyncGreetings)
    end
    layout:Checkbox(L.OPT_PANEL_STOP_ON_CLOSE,
        L.OPT_PANEL_STOP_ON_CLOSE_TIP,
        function() return audio().StopAudioOnDisengage end,
        function(value) audio().StopAudioOnDisengage = value end)
    layout:Checkbox(L.OPT_OG_THRALL,
        L.OPT_OG_THRALL_TIP,
        function() return audio().OGThrall end,
        function(value) audio().OGThrall = value end)

    -- The same two choices, labelled the same way, as SpokenBooks' panel: a player who
    -- sets the voice language in one looks for it in the same place in the other. Each
    -- lists the languages an installed pack speaks, since a language with no pack is a
    -- setting that can only narrate silence.
    layout:Section(L.OPT_SECTION_LANGUAGE)
    local voices = DataModules:GetOfferedLanguages(Language.AUTO, audio().VoiceLanguage)
    local fallbacks = DataModules:GetOfferedLanguages("none", audio().FallbackLanguage)
    layout:Dropdown(L.OPT_VOICE_LANGUAGE, L.OPT_VOICE_LANGUAGE_TIP,
        voices,
        function() return audio().VoiceLanguage or Language.AUTO end,
        function(code) audio().VoiceLanguage = code end,
        nil,
        function(code)
            if code == Language.AUTO then
                return format(L.OPT_LANG_AUTO_FMT, Language:GetNativeName(Language:GetClientLanguage()))
            end
            return Language:GetNativeName(code)
        end)
    layout:Dropdown(L.OPT_FALLBACK_LANGUAGE, L.OPT_FALLBACK_LANGUAGE_TIP,
        fallbacks,
        function() return audio().FallbackLanguage or Language.BASE end,
        function(code) audio().FallbackLanguage = code end,
        nil,
        function(code) return code == "none" and L.OPT_FALLBACK_NONE or Language:GetNativeName(code) end)

    -- The packs, inline. This used to be a branch of the options tree behind a button,
    -- which is two clicks and a second window to answer "is my audio installed".
    layout:Section(L.OPT_SECTION_PACKS)
    local packRows = {}
    -- A row reads like the other two addons': the pack's language, named for itself. The
    -- English "Spanish (EU)" a pack's Title carries is what its download page is called,
    -- not how the player picks its language, which is why the same pack reads Español
    -- (España) in Spoken Zones and Spoken Books. The English pack ships in five pieces,
    -- though -- a row that just read "English" for all five tells nobody which is which --
    -- so when a language is installed more than once, the piece's name sets the rows
    -- apart, the way Spoken Zones suffixes a bitrate to a language recorded at more than
    -- one.
    local function PackRowLabel(module)
        local share = 0
        for _, other in DataModules:GetPresentModules() do
            if other.Language == module.Language then
                share = share + 1
            end
        end
        local label = Language:GetNativeName(module.Language)
        if share > 1 then
            label = ("%s (%s)"):format(label,
                (string.gsub(module.Title, "Spoken Quests Audio: ", "")))
        end
        return label
    end
    local function DescribePacks()
        local present = 0
        for _, module in DataModules:GetPresentModules() do
            present = present + 1
            local row = packRows[present]
            if row then
                row.note:SetText(format("%s  |cff888888%s|r",
                    PackRowLabel(module), module.ContentVersion or ""))
                row.note:Show()
            end
        end
        for index = present + 1, table.getn(packRows) do
            packRows[index].note:Hide()
        end
        if present == 0 and packRows[1] then
            packRows[1].note:SetText(L.OPT_NO_PACK)
            packRows[1].note:Show()
        end
    end
    -- A row apiece, built once: the set of installed addons cannot change mid-session, and
    -- the panel is built after they have all loaded.
    local packCount = 0
    for _ in DataModules:GetPresentModules() do
        packCount = packCount + 1
    end
    for index = 1, math.max(packCount, 1) do
        packRows[index] = { note = layout:Note("", 460, 16) }
    end
    DescribePacks()
    content:SetScript("OnShow", DescribePacks)

    layout:Section(L.OPT_SECTION_TROUBLE)
    layout:Checkbox(L.OPT_PANEL_DEBUG,
        L.OPT_PANEL_DEBUG_TIP,
        function() return Addon.db.profile.DebugEnabled end,
        function(value) Addon.db.profile.DebugEnabled = value end)
    layout:Button(L.OPT_TEST_LINE, 200, function() Options:RunSelfTest() end,
        L.OPT_TEST_LINE_TIP)
    layout:Button(L.OPT_PRINT_DIAG, 200, function() Options:PrintDiagnostics() end,
        L.OPT_PRINT_DIAG_TIP)

    -- Profiles, inline. AceDB owns them; this is the whole of what its own options screen
    -- offered, minus the second window to reach it.
    local db = Addon.db
    if db.GetProfiles then
        layout:Section(L.OPT_SECTION_PROFILE)
        local function Others()
            local others, current = {}, db:GetCurrentProfile()
            for _, name in ipairs(db:GetProfiles()) do
                if name ~= current then
                    table.insert(others, name)
                end
            end
            return others
        end
        layout:Dropdown(L.OPT_PROFILE,
            L.OPT_PROFILE_TIP,
            function() return db:GetProfiles() end,
            function() return db:GetCurrentProfile() end,
            function(name) db:SetProfile(name) end)
        layout:Button(L.OPT_RESET_PROFILE, 200, function() db:ResetProfile() end,
            L.OPT_RESET_PROFILE_TIP)
        if db.CopyProfile then
            layout:Dropdown(L.OPT_COPY_PROFILE, L.OPT_COPY_PROFILE_TIP,
                Others,
                function() return nil end,
                function(name) db:CopyProfile(name) end,
                nil,
                function(name) return name or L.OPT_COPY_PICK end)
        end
        if db.DeleteProfile then
            layout:Dropdown(L.OPT_DELETE_PROFILE, L.OPT_DELETE_PROFILE_TIP,
                Others,
                function() return nil end,
                function(name) db:DeleteProfile(name) end,
                nil,
                function(name) return name or L.OPT_COPY_PICK end)
        end
    end

    -- Derived rather than written down: a hardcoded height is a number nobody updates
    -- when a row is added, and the failure it produces is a section you cannot reach.
    scroller:SetContentHeight(layout:Height() + 40)
    panel.content = content

    category = Settings.RegisterCanvasLayoutCategory(panel, "Spoken Quests")
    Settings.RegisterAddOnCategory(category)
    self.panel, self.category = panel, category
end

function SettingsPanel:Open()
    if category and Settings and Settings.OpenToCategory then
        local id = category.GetID and category:GetID() or nil
        if id and pcall(Settings.OpenToCategory, id) then
            return true
        end
        if pcall(Settings.OpenToCategory, category) then
            return true
        end
    end
    return false
end
