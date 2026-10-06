setfenv(1, SpokenEnv)

-- The DialogueUI page: Spoken > DialogueUI in the game's settings, beside the modules' pages,
-- with everything that is about the DialogueUI addon in one place. Spoken's own rows first --
-- the DialogueUI narrator style's window (UI/DialogueUIPlayer.lua) -- then a section from each
-- feature addon that registered one with Spoken:AddDialogueUISettings: Spoken_Quests' marks in
-- DialogueUI's own text, its player over DialogueUI's window and DialogueUI's Play button.
--
-- Only with DialogueUI loaded, and only where pages nest under Spoken's (the Settings API):
-- with neither there is nothing to set. Built at PLAYER_LOGIN with Spoken's own page, after
-- every feature addon has registered its rows; one registered later is added then.
--
-- Parsed by the 1.12 client too (addon.xml is shared), so Lua 5.0 syntax throughout; that
-- client has no DialogueUI and returns below.

DialogueUIOptions = { builders = {} }

if Version.IsAnyLegacy then
    function DialogueUIOptions:Add() end
    function DialogueUIOptions:Setup() end
    return
end

local Page = DialogueUIOptions
local Layout = SpokenLayout
local INDENT, TOP = 25, 16
-- After Quests, Books and Zones (1-3): not a part of Spoken, a companion's settings.
local ORDER = 4

local function IsLoaded(name)
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return isLoaded ~= nil and isLoaded(name) and true or false
end

local function Panel() return Addon.db.profile.Frame.DialogueUI end

--- Add a feature addon's rows. build(layout) adds a section and its rows to the page's
--- SpokenLayout, and may return a function that puts them back to their defaults, which the
--- page's Defaults button runs with Spoken's own.
function Page:Add(build)
    table.insert(self.builders, build)
    if self.layout then
        self:Run(build)
        self.layout:Refresh()
        self:Fit()
    end
end

function Page:Run(build)
    local ok, reset = pcall(build, self.layout)
    if ok and type(reset) == "function" then
        table.insert(self.resets, reset)
    elseif not ok then
        table.insert(Callbacks.errors, "DialogueUI settings: " .. tostring(reset))
    end
end

function Page:Fit()
    if self.scroller then self.scroller:SetContentHeight(self.layout:Height() + 40) end
end

--- The page's Defaults: Spoken's DialogueUI window settings, then each feature addon's.
function Page:Reset()
    local cfg = Panel()
    for key, value in pairs(Defaults.profile.Frame.DialogueUI) do cfg[key] = value end
    for _, reset in ipairs(self.resets) do pcall(reset) end
    if DialogueUIPlayer.frame then DialogueUIPlayer:SetExpanded(cfg.Expanded ~= false) end
    PlayerFrame:RefreshConfig()
    self.layout:Refresh()
end

function Page:Setup()
    if self.panel or not (Settings and Settings.RegisterCanvasLayoutSubcategory) or not IsLoaded("DialogueUI") then
        return
    end
    local panel = CreateFrame("Frame", "SpokenDialogueUIOptionsPanel", UIParent)
    panel.name = L.OPT_STYLE_DIALOGUEUI
    local scroller = Layout.Scroll(panel)
    local layout = Layout.New(scroller.child, INDENT, -TOP)
    panel.layout = layout
    self.panel, self.layout, self.scroller, self.resets = panel, layout, scroller, {}
    layout:Header(L.OPT_STYLE_DIALOGUEUI, nil, nil, nil)
    layout:HideHeader()
    layout:Intro(nil, L.OPT_STYLE_DIALOGUEUI)
    layout:Defaults(function() Page:Reset() end)

    local refresh = function() PlayerFrame:RefreshConfig(); layout:Refresh() end
    -- The window's rows wait on its style being the one chosen, and on DialogueUI being a
    -- version its art can be read from; the text's, on the words being shown at all.
    local function Window(row)
        layout:Requires(row, function() return DialogueUITheme:Available() end, L.OPT_STYLE_DUI_UNKNOWN)
        layout:Requires(row, function() return Addon:PlayerStyle() == "dialogueui" end, L.REASON_DUI_STYLE)
        return row
    end
    local function Words(row)
        Window(row)
        layout:Requires(row, function() return Addon:Profile("Transcript").Enabled end, L.REASON_WORDS)
        return row
    end

    layout:Section(L.OPT_WINDOW_TITLE)
    Window(layout:Checkbox(L.OPT_DUI_FOLLOW_THEME, L.OPT_DUI_FOLLOW_THEME_TIP,
        function() return Panel().FollowTheme end, function(v) Panel().FollowTheme = v end, refresh))
    layout:Indent()
    layout:Requires(Window(layout:Dropdown(L.OPT_DUI_THEME, L.OPT_DUI_THEME_TIP, { 1, 2 },
        function() return Panel().Theme end, function(v) Panel().Theme = v end, refresh,
        function(v) return v == 2 and L.OPT_DUI_THEME_DARK or L.OPT_DUI_THEME_PARCHMENT end)),
        function() return not Panel().FollowTheme end, L.REASON_DUI_FOLLOW)
    layout:Outdent()
    local sizes = DialogueUIPlayer.PANEL_SIZES
    Window(layout:Slider(L.OPT_DUI_SCALE, sizes[1], sizes[2], DialogueUIPlayer.SIZE_STEP,
        function() return Panel().Scale end, function(v) Panel().Scale = v end, refresh,
        nil, L.OPT_DUI_SCALE_TIP))
    Window(layout:Dropdown(L.OPT_DUI_MODE, L.OPT_DUI_MODE_TIP, { true, false },
        function() return Panel().Expanded end, function(v) Panel().Expanded = v end,
        -- Shown at once as it will open, folded or not.
        function() DialogueUIPlayer:SetExpanded(Panel().Expanded ~= false); refresh() end,
        function(v) return v == false and L.OPT_DUI_MODE_MINIMIZED or L.OPT_DUI_MODE_EXPANDED end))
    -- The folded panel's lines, the Small Window's Lines Shown for this window. Live whatever
    -- Opens As says: the corner button folds the panel either way.
    layout:Indent()
    Window(layout:Slider(L.TRANSCRIPT_LINES, 1, DialogueUIPlayer.MAX_MINIMIZED_LINES, 1,
        function() return Panel().MinimizedLines or 2 end, function(v) Panel().MinimizedLines = v end, refresh,
        Layout.Number, L.OPT_DUI_LINES_TIP))
    layout:Outdent()
    Window(layout:Checkbox(L.OPT_DUI_FIT_TEXT, L.OPT_DUI_FIT_TEXT_TIP,
        function() return Panel().FitText ~= false end, function(v) Panel().FitText = v end, refresh))
    -- The wheel shortcuts for Window Size and Text Size, which nothing on the window shows.
    layout:Note(L.DUI_WHEEL_HINT, nil, 40)

    layout:Section(L.OPT_TEXT_TITLE)
    Words(layout:Checkbox(L.OPT_DUI_LINK_FONT, L.OPT_DUI_LINK_FONT_TIP,
        function() return Panel().LinkFontScale end,
        function(v)
            -- Unlinked at the size the text has now, so nothing jumps.
            if not v and Panel().LinkFontScale ~= false then Panel().FontScale = Panel().Scale end
            Panel().LinkFontScale = v
        end, refresh))
    sizes = DialogueUIPlayer.FONT_SIZES
    layout:Indent()
    layout:Requires(Words(layout:Slider(L.OPT_DUI_FONT_SCALE, sizes[1], sizes[2], DialogueUIPlayer.SIZE_STEP,
        function() return Panel().FontScale end, function(v) Panel().FontScale = v end, refresh,
        nil, L.OPT_DUI_FONT_SCALE_TIP)),
        function() return Panel().LinkFontScale == false end, L.REASON_DUI_LINKED)
    layout:Outdent()

    for _, build in ipairs(self.builders) do self:Run(build) end

    scroller.child:SetScript("OnShow", function() layout:Refresh() end)
    layout:Refresh()
    self:Fit()
    self.page = Options:AddPage(panel, L.OPT_STYLE_DIALOGUEUI, ORDER, layout, scroller)
end

--- Open the page, from the button Spoken's own page shows while the DialogueUI style is chosen.
function Page:Open()
    return self.page ~= nil and Options:OpenPage(ORDER)
end
