-- The zones addon's narration across languages: an entry the active pack lacks, and where a
-- report on a clip goes. Language selection itself is older than this file and lives in
-- Language.lua. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local SPOKEN = here .. "/../../addons/SpokenPlayer/"
local ZONES = here .. "/../../addons/SpokenZones/"
local Expect, Failures = H.Expecter(print)

stub.SetClient("11509")
stub.LoadSpoken(SPOKEN)
stub.SetAddOns({ { folder = "SpokenZones", meta = { Version = "9.9.9" } } })

local MAP, BOTH, ONLY_ENGLISH = 1411, "valley of trials", "sen'jin village"

--- Load the addon with these packs, and these voice-acted overlays, installed.
local function Install(packs, overlays)
    _G.SpokenZonesDB = {}
    _G.SpokenZonesAudioPacks = {}
    _G.SpokenZonesAudioOverlays = overlays
    for _, pack in ipairs(packs) do
        _G.SpokenZonesAudioPacks[pack.addon] = pack
    end
    return H.LoadZones(ZONES)
end

local function Pack(addon, language, subzones)
    return { version = 1, addon = addon, language = language, bitrate = 128,
        zones = {}, subzones = { [MAP] = subzones } }
end

local ENGLISH = Pack("SpokenZonesAudio", "enUS", {
    [BOTH] = { file = "en-valley", len = 3 }, [ONLY_ENGLISH] = { file = "en-senjin", len = 3 } })
ENGLISH.zones[MAP] = { file = "en-durotar", len = 5 }
local GERMAN = Pack("SpokenZonesAudio_deDE", "deDE", { [BOTH] = { file = "de-valley", len = 3 } })
local FRENCH = Pack("SpokenZonesAudio_frFR", "frFR", { [ONLY_ENGLISH] = { file = "fr-senjin", len = 3 } })

---------------------------------------------------------------- A. the active pack, then English
local Z = Install({ ENGLISH, GERMAN, FRENCH })
stub.SetAddOns({ { folder = "SpokenZonesAudio_deDE", meta = { ["X-SpokenZones-Language"] = "deDE" } } })
Z:RegisterLoreData("enUS", "zones", { [MAP] = { name = "Durotar", full = "English zone lore." } })
Z:RegisterLoreData("enUS", "subzones", { [MAP] = {
    [BOTH] = { full = "English valley lore." }, [ONLY_ENGLISH] = { full = "English village lore." } } })
Z:RegisterLoreData("deDE", "subzones", { [MAP] = { [BOTH] = { full = "Deutsche Geschichte." } } })
Expect("A. installed voice metadata retains captions before that pack loads", Z:ShouldLoadLanguage("deDE"), true)
Expect("A. unrelated languages do not allocate caption tables", Z:ShouldLoadLanguage("frFR"), false)
Expect("A. registering captions leaves the lore browser's language alone", Z:GetLore(MAP).full, "English zone lore.")
Expect("A. zones carry their full text", Z:NewLoreSound(MAP, nil).present.transcript, "English zone lore.")
Z:SetActiveAudioPack("SpokenZonesAudio_deDE")
Expect("A. captions match the chosen voice, even when reading another language",
    Z:NewLoreSound(MAP, BOTH).present.transcript, "Deutsche Geschichte.")
Expect("A. fallback captions match the English audio",
    Z:NewLoreSound(MAP, ONLY_ENGLISH).present.transcript, "English village lore.")
local _, _, pack = Z:GetAudioClip(MAP, BOTH)
Expect("A. the active pack answers what it has", pack and pack.addon, "SpokenZonesAudio_deDE")
_, _, pack = Z:GetAudioClip(MAP, ONLY_ENGLISH)
Expect("A. an entry it lacks falls back to English, not to French", pack and pack.addon, "SpokenZonesAudio")

Z = Install({ ENGLISH, FRENCH })
Z:SetActiveAudioPack("SpokenZonesAudio")
Expect("A. an English pack falls back to nothing else", Z:GetAudioClip(MAP, "durotar coast"), nil)

---------------------------------------------------------------- B. the language narration plays in
Z = Install({ ENGLISH, GERMAN })
Z:SetActiveAudioPack("SpokenZonesAudio_deDE")
Expect("B. the active pack's language", Z:GetPackLanguage(), "deDE")
Z = Install({})
Expect("B. with no pack, the language being read", Z:GetPackLanguage(), Z:GetLanguage())

---------------------------------------------------------------- C. reports
Z = Install({ ENGLISH })
Expect("C. the lore window's report is filed under the language being read",
    Z:ReportURL(MAP, BOTH), "https://lore.rusty.one/" .. Z:GetLanguage() .. "/r/1411/valley-of-trials")
Expect("C. a clip's report under the language it was narrated in",
    Z:ReportURL(MAP, BOTH, "deDE"), "https://lore.rusty.one/deDE/r/1411/valley-of-trials")

---------------------------------------------------------------- D. contributions
Z = Install({ ENGLISH, GERMAN })
Z:SetActiveAudioPack("SpokenZonesAudio_deDE")
Z.Zones[1537] = { name = "Ironforge", pending = true }
local envelope = Z:CaptureContribution(1537, nil)
Expect("D. the locale is the client's", envelope:match("\nlocale=enUS\n") ~= nil, true)
Expect("D. ...and the language narration plays in goes beside it", envelope:match("\npack=deDE\n") ~= nil, true)

---------------------------------------------------------------- E. pack labels
-- One pack per language now, so a pack is named by the language it narrates, the one
-- being read included; bitrate only tells apart two packs in the same language.
Z = Install({ ENGLISH, GERMAN })
Expect("E. the pack in the language being read is named too", Z:GetAudioPackLabel(ENGLISH), "English")
Expect("E. another language by its own name", Z:GetAudioPackLabel(GERMAN), "Deutsch")
local RETIRED = Pack("ZoneLoreAudio64", "enUS", {})
RETIRED.bitrate = 64
Z = Install({ ENGLISH, RETIRED, GERMAN })
Expect("E. two packs in one language are told apart by bitrate", Z:GetAudioPackLabel(ENGLISH), "English (128 kbps)")
Expect("E. ...both of them", Z:GetAudioPackLabel(RETIRED), "English (64 kbps)")
Expect("E. a language with one pack still needs no bitrate", Z:GetAudioPackLabel(GERMAN), "Deutsch")

---------------------------------------------------------------- F. Auto follows the client, a pick does not
-- One SavedVariables file read by the same install switched between game languages. Auto
-- is stored as no language at all, so it answers each client with its own; anything the
-- player picked stays picked, whichever language the game runs in.
local READY = { { code = "enUS", ready = true }, { code = "esES", ready = true },
    { code = "frFR", ready = true } }
local function InstallOn(locale, db)
    stub.SetLocale(locale)
    _G.SpokenZonesDB = db
    _G.SpokenZonesAudioPacks = {}
    return H.LoadZones(ZONES, { Languages = READY })
end

local saved = {}
Z = InstallOn("esES", saved)
Expect("F. Auto is the default", Z:GetLanguagePreference(), nil)
Expect("F. ...and reads the client's language", Z:GetLanguage(), "esES")
Z = InstallOn("frFR", saved)
Expect("F. the same saved choice on a French client reads French", Z:GetLanguage(), "frFR")
Expect("F. ...and names it as what Auto reads", Z:GetAutoLanguage(), "frFR")
Z = InstallOn("koKR", saved)
Expect("F. a client whose translation is not finished reads English", Z:GetLanguage(), "enUS")
Expect("F. ...and Auto says so", Z:GetAutoLanguage(), "enUS")

Z = InstallOn("esES", saved)
Z:SetLanguage("esES")
Z = InstallOn("frFR", saved)
Expect("F. a language picked on one client stays on another", Z:GetLanguage(), "esES")
Expect("F. ...while Auto still names the client's own", Z:GetAutoLanguage(), "frFR")
Z:SetLanguage(nil)
Z = InstallOn("frFR", saved)
Expect("F. going back to Auto follows the client again", Z:GetLanguage(), "frFR")

stub.SetLocale("enUS")

---------------------------------------------------------------- G. voice-acted overlays
-- An overlay holds a voice actor's recording of some entries and nothing else. It is
-- registered the way a pack's build writes it: keyed by folder, no `addon` field.
local function Overlay(language, subzones, zones)
    return { version = 1, language = language, zones = zones or {}, subzones = { [MAP] = subzones },
        credits = { "Name A", "Name B" } }
end
local ACTED_DE = "SpokenZonesActed_deDE"
local ACTED_EN = "SpokenZonesActed"

Z = Install({ ENGLISH, GERMAN }, { [ACTED_DE] = Overlay("deDE", { [BOTH] = { file = "acted-valley", len = 4 } }) })
Z:SetActiveAudioPack("SpokenZonesAudio_deDE")
local path, length
path, length, pack = Z:GetAudioClip(MAP, BOTH)
Expect("G. an overlay's recording wins over the pack for an entry it has",
    path, [[Interface\AddOns\SpokenZonesActed_deDE\Sounds\acted-valley.mp3]])
Expect("G. ...with the overlay's own length", length, 4)
Expect("G. ...and the clip names the overlay's language, which its report is filed under",
    pack and pack.language, "deDE")
_, _, pack = Z:GetAudioClip(MAP, ONLY_ENGLISH)
Expect("G. an entry the overlay lacks falls through to the packs", pack and pack.addon, "SpokenZonesAudio")
_, _, pack = Z:GetAudioClip(MAP, nil)
Expect("G. ...zone lore too", pack and pack.addon, "SpokenZonesAudio")

-- The registry old clients read never holds an overlay, and this one keeps it out of every
-- list a pack is chosen from.
for _, listed in ipairs(Z:GetAudioPacks()) do
    Expect("G. an overlay is never listed as a pack", listed.addon ~= ACTED_DE, true)
end
Expect("G. an overlay cannot be made the active pack", Z:SetActiveAudioPack(ACTED_DE), false)
Expect("G. ...and the active pack stays the pack", Z:GetActiveAudioPack().addon, "SpokenZonesAudio_deDE")
Expect("G. overlays are listed on their own", Z:GetAudioOverlays()[1].addon, ACTED_DE)

-- Language before overlay: an English recording does not outrank the German pack.
Z = Install({ ENGLISH, GERMAN }, { [ACTED_EN] = Overlay("enUS", {
    [BOTH] = { file = "acted-en-valley", len = 4 }, [ONLY_ENGLISH] = { file = "acted-en-senjin", len = 4 } }) })
Z:SetActiveAudioPack("SpokenZonesAudio_deDE")
_, _, pack = Z:GetAudioClip(MAP, BOTH)
Expect("G. an English overlay does not outrank the German pack", pack and pack.addon, "SpokenZonesAudio_deDE")
_, _, pack = Z:GetAudioClip(MAP, ONLY_ENGLISH)
Expect("G. ...but answers the English fallback before the English pack", pack and pack.addon, ACTED_EN)

-- No pack at all: the overlay's few entries play, the rest say a pack is missing.
Z = Install({}, { [ACTED_EN] = Overlay("enUS", { [BOTH] = { file = "acted-en-valley", len = 4 } }) })
_, _, pack = Z:GetAudioClip(MAP, BOTH)
Expect("G. an overlay plays with no pack installed", pack and pack.addon, ACTED_EN)
Expect("G. ...and HasAudio says so, so the button shows", Z:HasAudio(MAP, BOTH), true)
Expect("G. ...an entry it lacks is silent", Z:GetAudioClip(MAP, ONLY_ENGLISH), nil)
Expect("G. ...and the overlay is still not a pack", Z:GetActiveAudioPack(), nil)
Expect("G. ...so the player is told to get one",
    Z:DescribeMissingAudio():match("no sound pack installed") ~= nil, true)
Expect("G. an overlay-only install narrates in the overlay's language", Z:GetPackLanguage(), "enUS")

-- An overlay-only install in a language other than the one being read still plays, the way
-- an English pack plays under German text.
Z = Install({}, { [ACTED_DE] = Overlay("deDE", { [BOTH] = { file = "acted-valley", len = 4 } }) })
_, _, pack = Z:GetAudioClip(MAP, BOTH)
Expect("G. an overlay in another language still plays alone", pack and pack.addon, ACTED_DE)
Expect("G. ...and is the language a contribution names", Z:GetPackLanguage(), "deDE")

-- A format this build cannot read is skipped, and the pack answers.
local future = Overlay("enUS", { [BOTH] = { file = "acted-en-valley", len = 4 } })
future.version = 2
Z = Install({ ENGLISH }, { [ACTED_EN] = future })
_, _, pack = Z:GetAudioClip(MAP, BOTH)
Expect("G. an overlay in an unknown format is ignored", pack and pack.addon, "SpokenZonesAudio")
Expect("G. ...and not listed", #Z:GetAudioOverlays(), 0)

-- /spz audio names an overlay and its voice actors, but never offers it as a switch.
Z = Install({ ENGLISH }, { [ACTED_DE] = Overlay("deDE", { [BOTH] = { file = "acted-valley", len = 4 } }) })
local chat = {}
local addMessage = DEFAULT_CHAT_FRAME.AddMessage
DEFAULT_CHAT_FRAME.AddMessage = function(_, message) table.insert(chat, message) end
SlashCmdList["SPOKENZONES"]("audio")
SlashCmdList["SPOKENZONES"]("audio " .. ACTED_DE)
DEFAULT_CHAT_FRAME.AddMessage = addMessage
local said = table.concat(chat, "\n")
Expect("G. /spz audio lists the overlay with its credits",
    said:find(ACTED_DE .. " -- Deutsch, voiced by Name A, Name B", 1, true) ~= nil, true)
Expect("G. ...and will not switch to it", said:find("is not an installed sound pack", 1, true) ~= nil, true)
Expect("G. ...leaving the pack active", Z:GetActiveAudioPack().addon, "SpokenZonesAudio")

_G.SpokenZonesAudioOverlays = nil

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll zones language tests passed")
