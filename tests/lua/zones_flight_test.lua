-- Exercise flight checks with real zone and queue code.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local Expect, Failures = H.Expecter(print)
local SPOKEN = here .. "/../../addons/Spoken/"
local ZONES = here .. "/../../addons/SpokenZones/"
local after = C_Timer.After
local onTaxi, flying = false, false

function UnitOnTaxi(unit)
    assert(unit == "player")
    return onTaxi
end
function IsFlying() return flying end

local function Boot(client, taxi, flight, greeting)
    stub.SetClient(client)
    stub.ResetSound(); stub.ResetTimers()
    stub.world.inCombat = false
    stub.world.playerLevel = 1
    onTaxi, flying = taxi, flight
    SpokenZonesSettings = nil
    SpokenZonesCharacter = greeting and {} or { greeted = true }
    SpokenZonesAudioPacks = {
        SpokenZonesAudio = { version = 1, addon = "SpokenZonesAudio", language = "enUS",
            zones = { [1411] = { file = "1411\\zone", len = 80 } },
            subzones = { [1411] = { ["valley of trials"] = { file = "1411\\valley", len = 35 } } } },
    }
    local env = stub.LoadSpoken(SPOKEN)
    env.Addon:Enable()
    C_Timer.After = after
    local Z = H.LoadZones(ZONES)
    assert(loadfile(ZONES .. "Locale/enUS.lua"))("SpokenZones", Z)
    assert(loadfile(ZONES .. "Autoplay.lua"))("SpokenZones", Z)
    Z.Zones[1411] = { name = "Durotar", full = "Durotar lore." }
    Z.Subzones[1411] = { ["valley of trials"] = { name = "Valley of Trials", full = "Valley lore." } }
    stub.SetZone({ map = 1411, zone = "Durotar", subzone = "Valley of Trials" })
    stub.FireEvent("ADDON_LOADED", "SpokenZones")
    Z:SetupAudio()
    Z:SetupAutoplay()
    return Z
end

-- IsFlying can be false on a taxi.
for _, state in ipairs({
    { name = "taxi", taxi = true, flying = false },
    { name = "flying mount", taxi = false, flying = true },
}) do
    for _, client in ipairs({ "11509", "20506", "16001" }) do
        local label = client .. " " .. state.name
        local Z = Boot(client, state.taxi, state.flying)
        stub.FireEvent("CHAT_MSG_SYSTEM", "Discovered Durotar.")
        stub.FireEvent("CHAT_MSG_SYSTEM", "Discovered Valley of Trials: 10 experience gained.")
        Expect(label .. ": discoveries queue nothing", Spoken:GetQueueSize(), 0)
        Expect(label .. ": skipped discoveries are not marked heard", Z:HeardCount(), 0)

        Z:Set("autoplayExplored", true)
        stub.FireEvent("ZONE_CHANGED_NEW_AREA")
        stub.FireEvent("ZONE_CHANGED")
        stub.FireEvent("ZONE_CHANGED_INDOORS")
        Expect(label .. ": explored zones and subzones queue nothing", Spoken:GetQueueSize(), 0)
        stub.Advance(3)
        Expect(label .. ": login's explored-area sweep queues nothing", Spoken:GetQueueSize(), 0)

        onTaxi, flying = false, false
        stub.Advance(1)
        Expect(label .. ": landing releases no flyover backlog", Spoken:GetQueueSize(), 0)
        stub.FireEvent("ZONE_CHANGED")
        Expect(label .. ": ground entry narrates the unheard zone and subzone", Spoken:GetQueueSize(), 2)
        Expect(label .. ": ground narration starts", Spoken:IsPlaying(), true)

        Z = Boot(client, state.taxi, state.flying, true)
        stub.Advance(2)
        Expect(label .. ": login greeting stays silent", Spoken:GetQueueSize(), 0)
        Expect(label .. ": skipped greeting is not spent", SpokenZonesCharacter.greeted, nil)
        onTaxi, flying = false, false
        stub.Advance(2)
        Expect(label .. ": greeting can retry on the ground", Spoken:IsPlaying(), true)
        Expect(label .. ": greeting is recorded after queueing", SpokenZonesCharacter.greeted, true)

        Z = Boot(client, state.taxi, state.flying)
        Expect(label .. ": manually requested lore still plays", Z:PlayLore(1411), true)
        Expect(label .. ": manual playback is audible", Spoken:IsPlaying(), true)
        local quests = Spoken:RegisterSource("quests", { title = "Quests", addon = "SpokenQuests" })
        local quest = H.Clip()
        quests:PlayNow(quest)
        Expect(label .. ": quest playback still works", Spoken:IsPlaying(quest), true)
    end
end

local Z = Boot("11509", false, false)
IsFlying = nil
onTaxi = true
stub.FireEvent("CHAT_MSG_SYSTEM", "Discovered Durotar.")
Expect("without IsFlying, taxis still suppress discoveries", Spoken:GetQueueSize(), 0)
onTaxi = false
stub.FireEvent("CHAT_MSG_SYSTEM", "Discovered Durotar.")
Expect("without IsFlying, ground discovery still plays", Spoken:IsPlaying(), true)

Z = Boot("11509", false, false)
UnitOnTaxi = nil
stub.FireEvent("CHAT_MSG_SYSTEM", "Discovered Durotar.")
Expect("missing flight APIs do not break ground discovery", Spoken:IsPlaying(), true)

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll zones flight tests passed")
