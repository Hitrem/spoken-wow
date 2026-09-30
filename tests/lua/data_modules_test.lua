-- How the quests addon finds its sound packs. A pack is discovered by a TOC key, never by
-- folder name, which is why the packs kept their names through the rename. The key itself
-- is being renamed, so both generations are read: the inherited X-VoiceOver-DataModule-*,
-- which every shipped pack and every third-party pack built for upstream carries, and
-- X-SpokenQuests-DataModule-*. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local QUESTS = here .. "/../../addons/SpokenQuests/"
local SPOKEN = here .. "/../../addons/SpokenPlayer/"
local Expect, Failures = H.Expecter(print)

local OLD, NEW = "X-VoiceOver-DataModule-", "X-SpokenQuests-DataModule-"

--- Install one pack carrying exactly the given TOC keys, and enumerate. `entry` is the
--- rest of what the client knows about it, such as having loaded its Lua already.
local function Enumerate(meta, entry)
    stub.SetClient("11509"); stub.ResetSound(); stub.ResetTimers()
    meta.Title = meta.Title or "TestPack"
    meta.Version = meta.Version or "1.2.1"
    entry = entry or {}
    entry.folder, entry.meta = "TestPack", meta
    stub.SetAddOns({ entry })
    local VO = stub.LoadQuests(QUESTS, SPOKEN)
    VO.DataModules:EnumerateAddons(false)
    return VO, VO.DataModules.presentModules["TestPack"]
end

---------------------------------------------------------------- the inherited key
local VO, found = Enumerate({ [OLD .. "Version"] = "1", [OLD .. "Priority"] = "5", [OLD .. "Maps"] = "1,2" })
Expect("a pack with the inherited key is found", found ~= nil, true)
Expect("...its format version is read", found and found.ModuleVersion, 1)
Expect("...its priority", found and found.ModulePriority, 5)
Expect("...and its maps", found and found.Maps[2], true)

---------------------------------------------------------------- the new key
VO, found = Enumerate({ [NEW .. "Version"] = "1", [NEW .. "Priority"] = "7", [NEW .. "Maps"] = "3" })
Expect("a pack with only the new key is found", found ~= nil, true)
Expect("...its format version is read", found and found.ModuleVersion, 1)
Expect("...its priority", found and found.ModulePriority, 7)
Expect("...and its maps", found and found.Maps[3], true)

---------------------------------------------------------------- both, as a transitional pack ships
-- A pack built during the transition carries both so it also loads under the old addon.
-- The values agree there; when they do not, the new key is the one this addon believes.
VO, found = Enumerate({ [OLD .. "Version"] = "1", [OLD .. "Priority"] = "5",
                        [NEW .. "Version"] = "1", [NEW .. "Priority"] = "7" })
Expect("a pack carrying both is found once", found ~= nil, true)
Expect("...and the new key wins", found and found.ModulePriority, 7)

---------------------------------------------------------------- key by key
-- The keys are read one at a time, so a pack may carry the new version key and nothing else.
VO, found = Enumerate({ [NEW .. "Version"] = "1", [OLD .. "Priority"] = "5" })
Expect("a missing new key falls back on its own", found and found.ModulePriority, 5)

---------------------------------------------------------------- registration
-- Register re-reads the version key to check the data format, and must find it either way.
VO = Enumerate({ [NEW .. "Version"] = "1" })
local ok = pcall(function() VO.DataModules:Register("TestPack", { GetSoundPath = function() end }) end)
Expect("a new-key pack can register its data", ok, true)

---------------------------------------------------------------- not a pack at all
VO, found = Enumerate({ Title = "Some other addon" })
Expect("an addon carrying neither key is not a pack", found, nil)

---------------------------------------------------------------- what a list can say about a pack
-- The panel and the options tree both name the packs they found, and a pack that is not
-- answering is one the client refused, one it loaded but that never registered, or one
-- nobody has got to. The player fixes those differently, and the third is the one a
-- player reads as a lie: their pack is plainly loaded and the list says otherwise.
VO, found = Enumerate({ [NEW .. "Version"] = "1" })
local L = VO.L
Expect("a pack nobody has tried to load yet says only that it is not loaded",
    VO.DataModules:GetModuleStatus("TestPack"), L.OPT_NOT_LOADED_SUFFIX)

-- Loaded by the client itself, which is what any pack without LoadOnDemand gets, and
-- whose Lua did not register. Nothing here can load it again, so the state is named.
VO, found = Enumerate({ [NEW .. "Version"] = "1" }, { loaded = true })
VO.DataModules:LoadPresentModules()
Expect("a pack the client loaded but that never registered says so",
    VO.DataModules:GetModuleStatus("TestPack"), " (LOADED_BUT_NOT_REGISTERED)")

-- Not loaded, and not loadable by hand: this one will not load without LoadOnDemand.
VO, found = Enumerate({ [NEW .. "Version"] = "1" })
VO.DataModules:LoadPresentModules()
Expect("a pack this cannot load says why",
    VO.DataModules:GetModuleStatus("TestPack"), " (NOT_LOAD_ON_DEMAND)")

VO, found = Enumerate({ [NEW .. "Version"] = "1" }, { loaded = true })
VO.DataModules:Register("TestPack", { GetSoundPath = function() end })
Expect("a pack that registered says nothing at all", VO.DataModules:GetModuleStatus("TestPack"), nil)

-- A pack the client loaded and that did register is the ordinary case, and the one that
-- used to be reported as a failure: the LoadOnDemand test ran before the loaded test,
-- so a healthy pack without LoadOnDemand was blamed for not having it.
VO, found = Enumerate({ [NEW .. "Version"] = "1" }, { loaded = true })
VO.DataModules:Register("TestPack", { GetSoundPath = function() end })
VO.DataModules:LoadPresentModules()
Expect("a working pack is never recorded as a failure",
    VO.DataModules:GetModuleLoadError("TestPack"), nil)

stub.ResetAddOns()
if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll data module tests passed")

---------------------------------------------------------------- what the voice pickers offer
-- A language with no pack is a setting that can only narrate silence, so the pickers list
-- the languages the installed packs speak. Two packs, two languages, and a third language
-- nobody installed: it must not be offered.
local function EnumeratePacks(packs)
    stub.SetClient("11509"); stub.ResetSound(); stub.ResetTimers()
    stub.SetAddOns(packs)
    local voice = stub.LoadQuests(QUESTS, SPOKEN)
    voice.DataModules:EnumerateAddons(false)
    return voice
end
local function Pack(folder, language)
    return { folder = folder, meta = { [NEW .. "Version"] = "1", Version = "1.0.0", Title = folder,
        ["X-SpokenQuests-Language"] = language } }
end

VO = EnumeratePacks({ Pack("PackEnglish"), Pack("PackGerman", "deDE") })
Expect("the pickers offer the languages an installed pack speaks",
    table.concat(VO.DataModules:GetOfferedLanguages("auto", nil), ","), "auto,enUS,deDE")
Expect("...in the order the language list gives, not the order they installed",
    table.concat(VO.DataModules:GetOfferedLanguages("auto", "deDE"), ","), "auto,enUS,deDE")

-- A pack that declares no language is an English pack, whatever its folder is called.
VO = EnumeratePacks({ Pack("PackEnglish") })
Expect("a pack that declares no language counts as English",
    table.concat(VO.DataModules:GetOfferedLanguages("auto", nil), ","), "auto,enUS")

-- A pack installed but out of date is still a pack the player has, so its language stays
-- offered; the pack list is where the fault is reported, not this dropdown.
local broken = Pack("PackBroken", "ruRU")
broken.loadable = false
VO = EnumeratePacks({ Pack("PackEnglish"), broken })
Expect("an installed pack is offered however it turned out",
    table.concat(VO.DataModules:GetOfferedLanguages("auto", nil), ","), "auto,enUS,ruRU")

-- A language the player chose and then uninstalled: still listed, or the control cannot
-- show what it is set to and the old options panel shows an empty dropdown.
VO = EnumeratePacks({ Pack("PackEnglish") })
Expect("a language with no pack is not offered",
    table.concat(VO.DataModules:GetOfferedLanguages("auto", nil), ","), "auto,enUS")
Expect("...except the one the player has stored, which must stay visible",
    table.concat(VO.DataModules:GetOfferedLanguages("auto", "koKR"), ","), "auto,enUS,koKR")
Expect("...and a stored language that is still installed is not listed twice",
    table.concat(VO.DataModules:GetOfferedLanguages("auto", "enUS"), ","), "auto,enUS")
Expect("...nor the dropdown's own entry, which is not a language",
    table.concat(VO.DataModules:GetOfferedLanguages("none", "none"), ","), "none,enUS")

-- A player with no packs at all is offered nothing but the dropdown's own entry, which is
-- the honest answer: Auto follows the client whatever is installed.
VO = EnumeratePacks({})
Expect("a player with no packs is offered no language",
    table.concat(VO.DataModules:GetOfferedLanguages("auto", nil), ","), "auto")

stub.ResetAddOns()
if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll offered language tests passed")
