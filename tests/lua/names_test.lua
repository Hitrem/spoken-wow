-- What the addons are called and where they keep their settings: Spoken and its modules,
-- grouped under it in the AddOns list, each starting fresh under names no older release used,
-- an old copy left in Interface\AddOns found and named, and one list of voice languages.
-- Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local Expect, Failures = H.Expecter(stub.print)
local ADDONS = here .. "/../../addons/"
local SPOKEN = ADDONS .. "Spoken/"
local QUESTS = ADDONS .. "SpokenQuests/"

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end
local function Field(toc, name)
    return string.match(Read(toc), "\n## " .. name .. ": ([^\r\n]*)")
end

---------------------------------------------------------------- in the AddOns list
local ADDON_TITLES = {
    { folder = "Spoken", title = "Spoken" },
    { folder = "SpokenQuests", title = "Spoken Quests" },
    { folder = "SpokenBooks", title = "Spoken Books" },
    { folder = "SpokenZones", title = "Spoken Zones" },
}
for _, addon in ipairs(ADDON_TITLES) do
    local toc = ADDONS .. addon.folder .. "/" .. addon.folder .. ".toc"
    Expect(addon.folder .. " is listed as " .. addon.title, Field(toc, "Title"), addon.title)
    Expect("...grouped under Spoken", Field(toc, "Group"), "Spoken")
end

---------------------------------------------------------------- settings under new names
-- A name an older release used would bring its settings back. Every addon starts fresh.
local SAVED = {
    { toc = "Spoken/Spoken.toc", vars = "SpokenSettings" },
    { toc = "SpokenQuests/SpokenQuests.toc", vars = "SpokenQuestsSettings" },
    { toc = "SpokenBooks/SpokenBooks.toc", vars = "SpokenBooksSettings", char = "SpokenBooksCharacter" },
    { toc = "SpokenZones/SpokenZones.toc", vars = "SpokenZonesSettings", char = "SpokenZonesCharacter" },
}
for _, addon in ipairs(SAVED) do
    Expect(addon.toc .. " saves " .. addon.vars, Field(ADDONS .. addon.toc, "SavedVariables"), addon.vars)
    Expect("...and per character " .. tostring(addon.char), Field(ADDONS .. addon.toc, "SavedVariablesPerCharacter"), addon.char)
end
-- Nothing ships under an old name any more, not even an empty folder.
Expect("no tombstone folders", io.open(ADDONS .. "tombstones/VoiceOverRedux/VoiceOverRedux.toc"), nil)

---------------------------------------------------------------- an old copy left behind
_G.UISpecialFrames = _G.UISpecialFrames or {}
stub.SetClient("11509"); stub.ResetSound(); stub.ResetTimers(); stub.ResetFrames()
stub.settingsCategories = {}; stub.ldbObjects = {}; stub.dbIcons = {}
stub.world.questID = 0; stub.ShowPanel(nil)
local VO = stub.LoadQuests(QUESTS, SPOKEN)
VO.Addon:OnInitialize()
local env = _G.SpokenEnv

local loaded = {}
local realLoaded = rawget(_G, "IsAddOnLoaded")
_G.IsAddOnLoaded = function(folder) return loaded[folder] == true end
stub.disabledAddOns = {}
Expect("nothing left behind, nothing found", table.getn(env.Addon:FindOldFolders()), 0)
loaded = { SpokenPlayer = true, VoiceOverRedux = true, ZoneLore = true, SpokenBooks = true, SpokenQuests = true }
local found = env.Addon:FindOldFolders()
Expect("every old folder is found, and no current one", table.concat(found, " "), "SpokenPlayer VoiceOverRedux ZoneLore")
Expect("...and none is disabled from here: the client would answer with its own dialog",
    table.getn(stub.disabledAddOns), 0)
_G.IsAddOnLoaded = realLoaded

---------------------------------------------------------------- one list of languages
-- Spoken's list replaces each module's own, so it has to offer every language they do.
local function Codes(list)
    local codes = {}
    for _, locale in ipairs(list) do table.insert(codes, locale.code) end
    return table.concat(codes, " ")
end
local function CodesIn(path)
    local block = string.match(Read(path), "LOCALES = (%b{})")
    local codes = {}
    for code in string.gmatch(block, 'code = "(%a+)"') do table.insert(codes, code) end
    return table.concat(codes, " ")
end
Expect("Spoken's languages are Quests', in the same order", Codes(env.LANGUAGES), CodesIn(QUESTS .. "Language.lua"))
Expect("...and Books'", Codes(env.LANGUAGES), CodesIn(ADDONS .. "SpokenBooks/Language.lua"))

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
