-- The DialogueUI narrator style (UI/DialogueUITheme.lua and UI/DialogueUIPlayer.lua): offered
-- only with DialogueUI, its window falling back to the small one without it, and with a fake
-- DialogueUI the window takes its size, its art, its theme and its font, follows a theme or
-- size change, sizes its text apart from itself, opens folded or not, shows a zone's or a
-- book's line as well as a quest's, and can be hosted over DialogueUI's window. Run with
-- `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local SPOKEN = here .. "/../../addons/Spoken/"
local Expect, Failures = H.Expecter(print)

local GOLD, RED = "|cffffd100", "|cff9c1a1a"
local BROWN, DARK = "Interface/AddOns/DialogueUI/Art/Theme_Brown/", "Interface/AddOns/DialogueUI/Art/Theme_Dark/"

---------------------------------------------------------------- a fake DialogueUI
local loaded = false
_G.IsAddOnLoaded = function(name) return name == "DialogueUI" and loaded end
local function FakeDialogueUI()
    _G.DialogueUI_DB = { Theme = 1, FrameSize = 2 }
    local frame = stub.Widget("Frame")
    -- DialogueUI's window at its default size on a 1080p screen, drawn at 0.8 scale.
    frame.frameWidth, frame.frameHeight = 624, 734
    frame.GetEffectiveScale = function() return 0.8 end
    local cap = stub.Widget("Texture")
    function cap:GetSize() return 601, 150 end
    frame.Parchments = { cap }
    function frame:LoadTheme() end
    function frame:UpdateFrameSize() end
    _G.DUIQuestFrame = frame
    local font = stub.Widget("Font")
    function font:GetFont() return "Interface/AddOns/DialogueUI/Fonts/frizqt__.ttf", 14 end
    _G.DUIFont_Quest_Paragraph = font
    return frame
end

local function Boot(client)
    stub.SetClient(client or "16001"); stub.ResetSound(); stub.ResetTimers(); stub.ResetFrames()
    stub.settingsCategories = {}; stub.ldbObjects = {}; stub.dbIcons = {}
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    -- A screen, for the window to take DialogueUI's share of; the stub's is a thumbnail.
    _G.UIParent:SetSize(1920, 1080)
    local env = stub.LoadSpoken(SPOKEN)
    -- LoadSpoken picks the large window for the other suites; these start from the small one.
    env.Addon.db.profile.Frame.Window = "minimal"
    env.Addon:Enable()
    local quests = env.Sources:Register("quests", { title = "Quests", addon = "Spoken_Quests", order = 1 })
    return env, quests
end

-- By label and tooltip: the DialogueUI window's Window Size and Text Size share their labels
-- with the other windows' rows they stand in for.
local function Row(layout, label, tooltip)
    for _, entry in ipairs(layout.entries) do
        if entry.label == label and (not tooltip or entry.tooltip == tooltip) then return entry.frame end
    end
end

---------------------------------------------------------------- without DialogueUI
local env = Boot()
local Spoken = _G.Spoken
Expect("the small window is the default window", Spoken:GetPlayerStyle(), "minimal")
Expect("no DialogueUI tile without DialogueUI", table.concat(env.Options:Styles(), ","), "subtitle,minimal,classic,none")
SlashCmdList.SPOKEN("player dialogueui")
Expect("the slash command says why it cannot switch", env.Addon.db.profile.Frame.Window, "minimal")
env.Addon.db.profile.Frame.Window = "dialogueui"
env.PlayerFrame:RefreshConfig()
Expect("a DialogueUI window chosen falls back to the small one", Spoken:GetPlayerStyle(), "minimal")
Expect("...the choice is kept, for DialogueUI coming back", env.Addon.db.profile.Frame.Window, "dialogueui")
Expect("...and the player frame is the small one", Spoken:GetPlayerFrame(), env.MinimalPlayer.frame)
Expect("...with the reason to hand", env.DialogueUITheme:Problem(), env.L.OPT_STYLE_DUI_MISSING)
Expect("no DialogueUI window is built for it", env.DialogueUIPlayer.frame, nil)

env = Boot("1.12")
Expect("the legacy client has the large window and nothing else", Spoken:GetPlayerStyle(), "classic")
Expect("...and no DialogueUI reading", env.DialogueUITheme:Available(), false)

---------------------------------------------------------------- the window, with DialogueUI
loaded = true
local DUI = FakeDialogueUI()
local quests
env, quests = Boot()
Spoken = _G.Spoken
Expect("with DialogueUI it is a fifth tile, after the large window",
    table.concat(env.Options:Styles(), ","), "subtitle,minimal,classic,dialogueui,none")
Expect("...named, described and drawn", env.Options.STYLE_LABELS.dialogueui ~= nil and env.Options.STYLE_TEXTS.dialogueui ~= nil
    and env.Options.STYLE_TIPS.dialogueui ~= nil and env.Options.SKETCHES.dialogueui ~= nil, true)
SlashCmdList.SPOKEN("player dialogueui")
local Skin, T = env.DialogueUIPlayer, env.Transcript
Expect("/spoken player dialogueui draws it", Spoken:GetPlayerStyle(), "dialogueui")
Expect("...remembered as the window chosen", env.Addon.db.profile.Frame.Window, "dialogueui")
Expect("...on its own frame", Spoken:GetPlayerFrame(), _G.SpokenDialogueUIPlayerFrame)
Expect("the window is laid out as DialogueUI's", Skin.frame:GetWidth(), 624)
Expect("...in height too", Skin.frame:GetHeight(), 734)
-- DialogueUI's window has no parent and is drawn at 0.8 here; UIParent at 1. Window Size
-- 0.65 of that is 0.52: the whole window scaled, not the player's Window Size.
Expect("...and its size scales the whole of it", math.abs(Skin.frame.scale - 0.52) < 1e-6, true)
Expect("the parchment is DialogueUI's own", Skin.parchments[2].texture, BROWN .. "Parchment.png")
Expect("...its top cap at the top of the image", table.concat(Skin.parchments[1].texCoord, ","), "0,1,0,0.125")
Expect("...its bottom cap where DialogueUI cuts it", table.concat(Skin.parchments[3].texCoord, ","), "0,1,0.4375,0.5625")
Expect("...sized as DialogueUI's", Skin.parchments[1].width, 601)
Expect("the words are DialogueUI's text size", T.style.size, 14)
Expect("...with its line spacing", T.style.lineGap, 5)
Expect("...and its paragraphs set apart", T.style.paragraphs, true)
T:SetClip({ text = "First paragraph.\nSecond one." })
Expect("an empty line separates two paragraphs", #T.lines == 3 and #T.lines[2] == 0, true)
T:SetClip(nil)
Expect("the words are docked in the window", T.frame:GetParent(), Skin.frame)
Expect("...filling its body", Skin.lines > 8, true)
Expect("...with labels enough for them and the line sliding in", #T.labels >= Skin.lines + 1, true)
Expect("...in DialogueUI's font", T.style.font, "Interface/AddOns/DialogueUI/Fonts/frizqt__.ttf")
Expect("...and the parchment's red highlight", T.style.highlight, RED)
Expect("the expand button has no place on a fixed page", T.expand:IsShown(), false)

-- The settings: the DialogueUI window's own on the DialogueUI page, Spoken > DialogueUI; on
-- Spoken's page, a button to it in place of the sizes the window does not use.
env.Options:UpdateRows()
local main, Page = _G.SpokenOptionsPanel.layout, env.DialogueUIOptions
main:Refresh()
local function Shown(layout, label, tooltip) local row = Row(layout, label, tooltip); return row ~= nil and row:IsShown() end
Expect("Spoken's page points to the DialogueUI page", Shown(main, env.L.OPT_DUI_OPEN_PAGE), true)
Expect("...which is listed after the modules' pages", Page.page and Page.page.order, 4)
Expect("...under DialogueUI's name", Page.page and Page.page.name, env.L.OPT_STYLE_DIALOGUEUI)
Expect("the small and large windows' size is not offered", Shown(main, env.L.OPT_SCALE, env.L.OPT_SCALE_TIP), false)
Expect("...nor their words' size and lines", Shown(main, env.L.TRANSCRIPT_SIZE, env.L.TRANSCRIPT_SIZE_TIP)
    or Shown(main, env.L.TRANSCRIPT_LINES), false)
Expect("...but how the words scroll is", Shown(main, env.L.TRANSCRIPT_SCROLL), true)
local page = Page.layout
page:Refresh()
local function Live(label, tooltip) local row = Row(page, label, tooltip); return row ~= nil and row.layoutReason == nil end
Expect("the page has the window's size", Live(env.L.OPT_DUI_SCALE, env.L.OPT_DUI_SCALE_TIP), true)
Expect("...its theme", Live(env.L.OPT_DUI_FOLLOW_THEME), true)
Expect("...how it opens", Live(env.L.OPT_DUI_MODE), true)
Expect("...and its text's size", Live(env.L.OPT_DUI_LINK_FONT), true)
Expect("the theme waits on not following DialogueUI's", Row(page, env.L.OPT_DUI_THEME).layoutReason, env.L.REASON_DUI_FOLLOW)
Expect("the text size waits on unlinking it",
    Row(page, env.L.OPT_DUI_FONT_SCALE, env.L.OPT_DUI_FONT_SCALE_TIP).layoutReason, env.L.REASON_DUI_LINKED)
env.Addon:SetPlayerStyle("minimal")
page:Refresh()
Expect("with another style chosen they wait on this one, saying where to choose it",
    Row(page, env.L.OPT_DUI_SCALE, env.L.OPT_DUI_SCALE_TIP).layoutReason, env.L.REASON_DUI_STYLE)
env.Addon:SetPlayerStyle("dialogueui")
env.Addon.db.profile.Frame.DialogueUI.Scale = 0.9
Page:Reset()
Expect("the page's Defaults puts the window's settings back", env.Addon.db.profile.Frame.DialogueUI.Scale, 0.65)

---------------------------------------------------------------- folded or open
Skin:SetExpanded(false)
Expect("folded, the window keeps two lines", Skin.lines, 2)
Expect("...and shrinks to them", Skin.frame:GetHeight() < 734, true)
Expect("...for the session: the setting is unchanged", env.Addon.db.profile.Frame.DialogueUI.Expanded, true)
Skin:SetExpanded(true)
Expect("...and opens back up", Skin.lines > 8, true)
env.Addon.db.profile.Frame.DialogueUI.Expanded = false
env.PlayerFrame:Reset()
Expect("set to open minimized, it opens folded", Skin.lines, 2)
env.Addon.db.profile.Frame.DialogueUI.Expanded = true
env.PlayerFrame:Reset()
Expect("...and set to open expanded, open", Skin.lines > 8, true)

local saved = env.Addon:Layout()
saved.DialogueUIHeight = 900
env.PlayerFrame:RefreshConfig()
Expect("a dragged height is kept", Skin.frame:GetHeight(), 900)
Expect("...and the words fill it", Skin.lines > 8, true)
Expect("...with labels enough for them", #T.labels >= Skin.lines, true)
saved.DialogueUIHeight = nil
saved.DialogueUIWidth = 700
env.PlayerFrame:RefreshConfig()
Expect("a width dragged with Shift is kept", Skin.frame:GetWidth(), 700)
local faceAtDefault = Skin.portrait.width
Expect("...the paper stretching with it", math.abs(Skin.parchments[1].width - 601 * 700 / 624) < 0.01, true)
local socketAtDefault = Skin.headerSocket.width
Expect("...and the header line", Skin.headerDivider.width + Skin.headerSocket.width > 600, true)
saved.DialogueUIWidth = 100
env.PlayerFrame:RefreshConfig()
Expect("...but never narrower than the header can hold", Skin.frame:GetWidth(), math.floor(624 * 0.6 + 0.5))
Expect("the face keeps its size whatever the width", Skin.portrait.width, faceAtDefault)
Expect("...and so does the socket it sits in", Skin.headerSocket.width, socketAtDefault)
saved.DialogueUIWidth = nil
env.PlayerFrame:RefreshConfig()

---------------------------------------------------------------- what it shows
env.Options:Preview("dialogueui")
Expect("previewing the tile shows the window with a sample line", Skin.wanted, true)
Expect("...its speaker", Skin.name:GetText(), env.L.SAMPLE_SPEAKER)
env.Options:Preview(nil)
Expect("...and puts it away", Skin.wanted, false)

local clip = H.Clip({ present = { header = "Eagan Peltskinner", label = "Wolves Across the Border",
    bullet = "quest-accept", portrait = { kind = "none" } } })
quests:Enqueue(clip)
Expect("a queued line shows the window", Skin.wanted, true)
Expect("...naming the speaker", Skin.name:GetText(), "Eagan Peltskinner")
Expect("...and the line", Skin.title.text:GetText(), "Wolves Across the Border")
quests:Enqueue(H.Clip({ present = { header = "Eagan", label = "Second", portrait = { kind = "none" } } }))
Expect("a waiting line gets a row", Skin.rows[1] and Skin.rows[1]:IsShown(), true)
Expect("...reading its label", Skin.rows[1].text:GetText(), "Second")
Spoken:StopAll()

-- A book page or a zone's lore, as Spoken_Books and Spoken_Zones queue them: the book for a
-- face, a title and no NPC; a single-page book without even a page label.
local books = env.Sources:Register("books", { title = "Books", addon = "Spoken_Books", order = 3 })
books:Enqueue({ key = "b:1", path = "b1.mp3", length = 6, present = { header = "A Letter Home", transcript = "Dear mother, the war goes well.",
    bullet = "book", portrait = { kind = "texture", texture = [[Interface\AddOns\Spoken\Textures\Book]] } } })
Expect("a book page shows the window", Skin.wanted, true)
Expect("...titled by the book", Skin.name:GetText(), "A Letter Home")
Expect("...and named by its key when it has no page label", Skin.title.text:GetText(), "b:1")
Expect("...the book for a face", Skin.viewport.active, "texture")
Expect("...with its words in the window", T.text, "Dear mother, the war goes well.")
Spoken:StopAll()
local zones = env.Sources:Register("zones", { title = "Zones", addon = "Spoken_Zones", order = 2 })
zones:Enqueue({ key = "z:12", path = "z12.ogg", length = 20, present = { header = "Elwynn Forest", label = "Goldshire",
    bullet = "zone", portrait = { kind = "texture", texture = [[Interface\AddOns\Spoken\Textures\Book]] } } })
Expect("a zone's lore shows it too", Skin.name:GetText() .. "/" .. Skin.title.text:GetText(), "Elwynn Forest/Goldshire")
Expect("...even with no words to show", T.frame:IsShown(), false)
Spoken:StopAll()

---------------------------------------------------------------- DialogueUI's theme and size
_G.DialogueUI_DB.Theme = 2
DUI:LoadTheme()
Expect("DialogueUI switching to dark switches the window", Skin.parchments[2].texture, DARK .. "Parchment.png")
Expect("...and the highlight to gold", T.style.highlight, GOLD)
_G.DialogueUI_DB.Theme = 1
DUI:LoadTheme()
local dui = env.Addon.db.profile.Frame.DialogueUI
dui.FollowTheme, dui.Theme = false, 2
env.PlayerFrame:RefreshConfig()
Expect("not following, the chosen theme wins over DialogueUI's", Skin.parchments[2].texture, DARK .. "Parchment.png")
dui.FollowTheme = true

DUI.frameWidth, DUI.frameHeight = 600, 700
DUI:UpdateFrameSize()
Expect("DialogueUI resizing resizes the window", Skin.frame:GetWidth(), 600)
dui.Scale = 0.3
env.PlayerFrame:RefreshConfig()
Expect("a smaller size scales it down", math.abs(Skin.frame.scale - 0.3 * 0.8) < 1e-6, true)
Expect("...keeping DialogueUI's layout inside", Skin.frame:GetWidth(), 600)
dui.Scale = 0.65
env.PlayerFrame:RefreshConfig()
dui.LinkFontScale, dui.FontScale = false, 1.3
env.PlayerFrame:RefreshConfig()
-- Drawn at 0.65, a 14 that should read as 1.3 of DialogueUI's is set at 28.
Expect("unlinked, Text Size sets the words on their own", T.style.size, 28)
Expect("...their spacing following", T.style.lineGap, 10)
Expect("...the window keeping its scale", math.abs(Skin.frame.scale - 0.52) < 1e-6, true)
dui.Scale = 0.3
env.PlayerFrame:RefreshConfig()
Expect("...and a smaller window leaving the text as it reads", T.style.size, 61)
dui.Scale, dui.LinkFontScale = 0.65, true
env.PlayerFrame:RefreshConfig()
Expect("linked again, the words are DialogueUI's size in the window", T.style.size, 14)

-- The wheel with Ctrl held over the window. Ctrl alone sizes the window, keeping its top left
-- corner on screen; Shift with it sizes the text and unlinks it.
local ctrl, shift = false, false
_G.IsControlKeyDown = function() return ctrl end
_G.IsShiftKeyDown = function() return shift end
T.top = 1
T.frame:GetScript("OnMouseWheel")(T.frame, -1)
Expect("the wheel alone still scrolls the words", T.manualScroll, true)
Expect("...the size untouched", dui.Scale, 0.65)
ctrl = true
T.frame:GetScript("OnMouseWheel")(T.frame, 1)
Expect("Ctrl and the wheel over the words grow the window", math.abs(dui.Scale - 0.7) < 1e-9, true)
Expect("...drawing it larger", math.abs(Skin.frame.scale - 0.7 * 0.8) < 1e-6, true)
Expect("...its corner kept where it was", math.abs(Skin.frame.anchor.y - 100 * 0.52 / 0.56) < 1e-6, true)
Expect("...the text still linked", dui.LinkFontScale, true)
Expect("...and saying so", _G.GameTooltip.text, env.L.OPT_DUI_SCALE .. ": 70%")
dui.Scale = 1.2
Skin.frame:GetScript("OnMouseWheel")(Skin.frame, 1)
Expect("...no further than the slider goes", dui.Scale, 1.2)
dui.Scale = 0.65
env.PlayerFrame:RefreshConfig()
shift = true
Skin.frame:GetScript("OnMouseWheel")(Skin.frame, 1)
Expect("Ctrl, Shift and the wheel unlink the text", dui.LinkFontScale, false)
Expect("...and grow it from the window's size", math.abs(dui.FontScale - 0.7) < 1e-9, true)
Expect("...the window left alone", dui.Scale, 0.65)
Expect("...and the words set larger", T.style.size, 15)
ctrl, shift = false, false
dui.LinkFontScale = true
env.PlayerFrame:RefreshConfig()

---------------------------------------------------------------- over DialogueUI's window
Spoken:SetPlayerHost(DUI)
Expect("hosted over DialogueUI the window moves onto it", Skin.frame:GetParent(), DUI)
Expect("...at its size of the window it sits on", math.abs(Skin.frame.scale - 0.65) < 1e-6, true)
Expect("...and is locked there", env.Addon:IsFrameLocked(), true)
Spoken:SetPlayerHost(nil)
Expect("...and comes back", Skin.frame:GetParent(), _G.UIParent)
Expect("...at its own scale", math.abs(Skin.frame.scale - 0.52) < 1e-6, true)

Expect("diagnostics name the style", string.find(Skin:Describe(), "enabled=true", 1, true) ~= nil, true)
Expect("...and the theme reading", string.find(env.DialogueUITheme:Describe(), "theme=1", 1, true) ~= nil, true)

SlashCmdList.SPOKEN("player minimal")
quests:Enqueue(H.Clip({ present = { header = "Eagan", label = "Back", portrait = { kind = "none" } } }))
Expect("switching back hides the DialogueUI window", Skin.frame:IsShown(), false)
Expect("...shows the small one", env.MinimalPlayer.frame:IsShown(), true)
Expect("...and moves the words with it", T.frame:GetParent(), env.MinimalPlayer.frame)
Expect("...in their own look again", T.style, nil)
Spoken:StopAll()

loaded = false
env.Addon.db.profile.Frame.Window = "dialogueui"
env.PlayerFrame:RefreshConfig()
Expect("DialogueUI gone, the window stands down", Skin.frame:IsShown(), false)
Expect("...for the small one", Spoken:GetPlayerStyle(), "minimal")

if Failures() > 0 then
    print(string.format("\n%d DialogueUI style test(s) failed", Failures()))
    os.exit(1)
end
print("\nAll DialogueUI style tests passed")
