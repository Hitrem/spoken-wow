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
-- Always the last entry under Spoken: not a part of Spoken, a companion's settings. The game
-- lists pages in the order they are registered, and Spoken_Books registers its page at
-- PLAYER_ENTERING_WORLD, after this page is built; so this one is registered a frame after
-- that event, once the parts' pages are in.
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
-- After every part's page (Quests, Books and Zones are 1-3).
local ORDER = 1000

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
    PlayerFrame:RefreshConfig()
    self.layout:Refresh()
end

function Page:Setup()
    if self.panel or not (Settings and Settings.RegisterCanvasLayoutSubcategory) or not DialogueUITheme:Installed() then
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
    -- version its art can be read from. Its size, text size and lines are not here: they are
    -- the player's own settings on Spoken's page, which this window follows as the others do.
    local function Window(row)
        layout:Requires(row, function() return DialogueUITheme:Available() end, L.OPT_STYLE_DUI_UNKNOWN)
        layout:Requires(row, function() return Addon:PlayerStyle() == "dialogueui" end, L.REASON_DUI_STYLE)
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
    Window(layout:Checkbox(L.OPT_DUI_FIT_TEXT, L.OPT_DUI_FIT_TEXT_TIP,
        function() return Panel().FitText ~= false end, function(v) Panel().FitText = v end, refresh))
    -- The wheel shortcuts for Window Size and Text Size, which nothing on the window shows.
    layout:Note(L.DUI_WHEEL_HINT, nil, 40)

    for _, build in ipairs(self.builders) do self:Run(build) end

    scroller.child:SetScript("OnShow", function() layout:Refresh() end)
    layout:Refresh()
    self:Fit()
    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("PLAYER_ENTERING_WORLD")
    waiter:SetScript("OnEvent", function()
        waiter:UnregisterAllEvents()
        C_Timer.After(0, function() Page:Register() end)
    end)
end

function Page:Register()
    if self.page or not self.panel then return end
    self.page = Options:AddPage(self.panel, L.OPT_STYLE_DIALOGUEUI, ORDER, self.layout, self.scroller)
end

--- Open the page, from the button Spoken's own page shows while the DialogueUI style is chosen.
function Page:Open()
    self:Register()
    return self.page ~= nil and Options:OpenPage(ORDER)
end
