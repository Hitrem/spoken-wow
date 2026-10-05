-- Which places a character has found, for Lore of Azeroth's list: explored areas read off the
-- zone maps, places stood in since, and a city found by its name on the zone around it. Run
-- with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local Expect, Failures = H.Expecter(stub.print)
local ZONES = here .. "/../../addons/Spoken_Zones/"

stub.SetClient("11509"); stub.ResetSound(); stub.ResetTimers(); stub.ResetFrames()

-- Durotar's map, 1000 by 500, with two explored overlays: the Valley of Trials, and Orgrimmar's
-- gate at the top. Nothing explored on Dun Morogh's map, and none on Orgrimmar's own (cities have
-- no overlays).
local AREAS = { [1] = "Valley of Trials", [2] = "Orgrimmar" }
local OVERLAYS = {
    [1411] = {
        { hitRect = { left = 100, right = 300, top = 300, bottom = 450 }, area = 1 },
        { hitRect = { left = 400, right = 600, top = 0, bottom = 100 }, area = 2 },
    },
}
_G.CreateVector2D = function(x, y) return { x = x, y = y } end
_G.C_Map = _G.C_Map or {}
C_Map.GetMapArtLayers = function() return { { layerWidth = 1000, layerHeight = 500 } } end
C_Map.GetAreaInfo = function(id) return AREAS[id] end
_G.C_MapExplorationInfo = {
    GetExploredMapTextures = function(mapID) return OVERLAYS[mapID] or {} end,
    GetExploredAreaIDsAtPosition = function(mapID, at)
        for _, o in ipairs(OVERLAYS[mapID] or {}) do
            local r = o.hitRect
            local px, py = at.x * 1000, at.y * 500
            if px >= r.left and px <= r.right and py >= r.top and py <= r.bottom then return { o.area } end
        end
        return nil
    end,
}

local where = { map = 1411, subzone = "" }
_G.GetSubZoneText = function() return where.subzone end
local Z = { Zones = { [1411] = {}, [1426] = {}, [1454] = {} }, Subzones = { [1411] = { ["valley of trials"] = {}, ["razor hill barracks"] = {}, ["orgrimmar"] = {} },
    [1426] = { ["coldridge valley"] = {} } } }
local names = { [1411] = "Durotar", [1426] = "Dun Morogh", [1454] = "Orgrimmar" }
local settings = {}
function Z:Get(key) return settings[key] end
function Z:GetMapName(mapID) return names[mapID] end
function Z:ResolveAreaKey(name) return name and string.lower(name) end
function Z:GetPlayerMapID() return where.map end
function Z:GetLoreWithFallback(mapID) return {}, mapID end
function Z:GetSubzoneLore(mapID, name)
    local key = string.lower(name)
    if self.Subzones[mapID] and self.Subzones[mapID][key] then return {}, key end
end
local onZone
function Z:OnZoneChanged(fn) onZone = fn end
_G.SpokenZonesCharacter = nil
assert(loadfile(ZONES .. "Discovery.lua"))("SpokenZones", Z)
Z:SetupDiscovery()

-- The city first, before anything has read Durotar's map.
Expect("a city is found by its name explored on the zone around it, whichever is asked first", Z:IsFound(1454), true)
Expect("an explored area is found", Z:IsFound(1411, "valley of trials"), true)
Expect("...and its zone", Z:IsFound(1411), true)
Expect("an area with no overlay is not found before it is stood in", Z:IsFound(1411, "razor hill barracks"), false)
Expect("a zone with nothing explored is not found", Z:IsFound(1426), false)

where.subzone = "Razor Hill Barracks"
onZone()
Expect("standing in a place finds it", Z:IsFound(1411, "razor hill barracks"), true)
Expect("...kept for the character", SpokenZonesCharacter.visited["1411/razor hill barracks"], true)

where.map, where.subzone = 1426, "Coldridge Valley"
onZone()
Expect("standing in an unexplored zone finds it", Z:IsFound(1426), true)
Expect("...and the area stood in", Z:IsFound(1426, "coldridge valley"), true)

Expect("undiscovered places hidden unless the setting says", Z:ShowsUndiscovered(), false)
settings.showUndiscovered = true
Expect("...shown when it does", Z:ShowsUndiscovered(), true)

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll discovery tests passed")
