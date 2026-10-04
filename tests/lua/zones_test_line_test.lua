-- The zones page's Test line and Start Over, with the addon's Core.lua loaded for real. Run
-- with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local SPOKEN = here .. "/../../addons/Spoken/"
local ZONES = here .. "/../../addons/SpokenZones/"
local Expect, Failures = H.Expecter(print)

stub.SetClient("11509")
stub.LoadSpoken(SPOKEN)
local Z = H.LoadZones(ZONES)
_G.SpokenZonesSettings = { voiceEnabled = true }
local printed = {}
Z.Print = function(_, fmt, ...)
    table.insert(printed, select("#", ...) > 0 and fmt:format(...) or fmt)
end

---------------------------------------------------------------- Test line
-- No voice pack: every story lacks a clip. Trying each in turn printed why, once per zone.
Z.Zones = {}
for id = 1, 50 do Z.Zones[id] = { name = "Zone " .. id } end
Z:PlayTestLine()
Expect("with no voice pack, the test line says so once", #printed, 1)
Expect("...naming the missing pack", printed[1] and printed[1]:find("no sound pack installed", 1, true) ~= nil, true)

-- A pack covering one story far down the list: that one plays, and nothing is printed for the
-- ones before it.
printed = {}
local tried = {}
Z.HasAudio = function(_, mapID) return mapID == 40 end
Z.PlayLore = function(_, mapID) table.insert(tried, mapID); return true end
Z:PlayTestLine()
Expect("the first story with a clip is the one played", table.concat(tried, ","), "40")
Expect("...without a word about the others", #printed, 0)

---------------------------------------------------------------- Start Over
-- The page's reset writes the defaults and applies them, as the checkboxes do.
local applied, notified = 0, 0
Z.ApplyMinimapButton = function() applied = applied + 1 end
Z.NotifyAudioChanged = function() notified = notified + 1 end
_G.SpokenZonesSettings.showMinimapButton = false
_G.SpokenZonesSettings.voiceEnabled = false
Z:ResetOptions()
Expect("a reset brings the minimap button setting back", _G.SpokenZonesSettings.showMinimapButton, true)
Expect("...and shows the button rather than waiting for a reload", applied, 1)
Expect("...and the play buttons hear the voice is on again", notified, 1)

os.exit(Failures() == 0 and 0 or 1)
