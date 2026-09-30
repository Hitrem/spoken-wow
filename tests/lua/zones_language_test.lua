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

--- Load the addon with these packs installed.
local function Install(packs)
    _G.SpokenZonesDB = {}
    _G.SpokenZonesAudioPacks = {}
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

---------------------------------------------------------------- A1. the voice preference, and Auto
-- The voice picker lists packs and has an Auto entry, so it needs to tell "nothing stored"
-- from "a pack stored that is no longer installed". Both are Auto to the player, and only
-- one of them is a choice.
Z = Install({ ENGLISH, GERMAN, FRENCH })
Expect("A1. nothing stored is Auto", Z:GetPreferredAudioPack(), nil)
Z:SetActiveAudioPack("SpokenZonesAudio_frFR")
Expect("A1. a chosen pack is the preference",
    (Z:GetPreferredAudioPack() or {}).addon, "SpokenZonesAudio_frFR")
Expect("A1. ...and is what plays, whatever the sort would have preferred",
    (Z:GetActiveAudioPack() or {}).addon, "SpokenZonesAudio_frFR")
Expect("A1. a name that is not an installed pack is refused",
    Z:SetActiveAudioPack("SpokenZonesAudio_nope"), false)
Expect("A1. ...leaving the preference alone",
    (Z:GetPreferredAudioPack() or {}).addon, "SpokenZonesAudio_frFR")
-- Handing the choice back, which there was no way to do before: choosing a pack stored a
-- folder name and nothing stored it as absent again.
Expect("A1. Auto hands the choice back", Z:SetActiveAudioPack(nil), true)
Expect("A1. ...so the preference is gone", Z:GetPreferredAudioPack(), nil)
Expect("A1. ...and the best installed pack takes over",
    (Z:GetActiveAudioPack() or {}).addon, "SpokenZonesAudio")
-- Stored but uninstalled: the pack the player asked for is not there, and the pack that
-- plays is not what they asked for either. It reads as Auto in the picker, which is the
-- only honest caption -- but the note under it lists what is installed, so the gap shows.
Z:SetActiveAudioPack("SpokenZonesAudio_frFR")
Z = Install({ ENGLISH, GERMAN })
Expect("A1. a pack that has been uninstalled is not a preference",
    Z:GetPreferredAudioPack(), nil)
Expect("A1. ...and the best remaining pack plays",
    (Z:GetActiveAudioPack() or {}).addon, "SpokenZonesAudio")

---------------------------------------------------------------- A2. the fallback is a setting
-- It was always English, and English is still the default, because every published pack is
-- English or a translation of the English corpus. What changed is that the player can now
-- say otherwise -- and can say nothing at all.
Z = Install({ ENGLISH, GERMAN, FRENCH })
Z:SetActiveAudioPack("SpokenZonesAudio_deDE")
Expect("A2. English is the fallback until the player says otherwise",
    Z:GetFallbackLanguage(), "enUS")
_, _, pack = Z:GetAudioClip(MAP, ONLY_ENGLISH)
Expect("A2. ...so an entry only the English pack has still plays", pack and pack.addon, "SpokenZonesAudio")
Z:SetFallbackLanguage("frFR")
_, _, pack = Z:GetAudioClip(MAP, ONLY_ENGLISH)
Expect("A2. a French fallback is used instead of English", pack and pack.addon, "SpokenZonesAudio_frFR")
Z:SetFallbackLanguage("none")
Expect("A2. ...and None plays nothing rather than English", Z:GetAudioClip(MAP, ONLY_ENGLISH), nil)
Expect("A2. the pack the player chose is still preferred over the fallback",
    (select(3, Z:GetAudioClip(MAP, BOTH))).addon, "SpokenZonesAudio_deDE")
-- A fallback naming the pack's own language changes nothing: it is the same pack asked
-- twice, and asking twice would let a stale entry shadow a good one.
Z:SetFallbackLanguage("deDE")
_, _, pack = Z:GetAudioClip(MAP, ONLY_ENGLISH)
Expect("A2. a fallback in the pack's own language is not asked twice", pack and pack.addon, nil)

Z = Install({ ENGLISH, GERMAN, FRENCH })
Z:SetActiveAudioPack("SpokenZonesAudio_deDE")
Z:SetFallbackLanguage("ruRU")
_, _, pack = Z:GetAudioClip(MAP, ONLY_ENGLISH)
Expect("A2. a fallback with no pack installed falls through to silence",
    pack and pack.addon, nil)

--- What the fallback picker offers: None, then every language an installed pack speaks.
Z = Install({ ENGLISH, GERMAN })
Expect("A2. the picker offers None and the languages a pack speaks",
    table.concat(Z:GetOfferedFallbackLanguages(nil), ","), "none,enUS,deDE")
Expect("A2. ...in the language list's order, not the order they installed",
    table.concat(Z:GetOfferedFallbackLanguages("deDE"), ","), "none,enUS,deDE")
-- A pack published before languages existed carries no language, and is English.
local LEGACY = Install({ ENGLISH, Pack("SpokenZonesAudioLegacy", nil, {}) })
Expect("A2. a pack declaring no language counts as English",
    table.concat(LEGACY:GetOfferedFallbackLanguages(nil), ","), "none,enUS")
Z = Install({ ENGLISH, GERMAN })
-- A language the player chose and then uninstalled: still listed, or the control cannot
-- show what it is set to and the dropdown reads as empty.
Expect("A2. a language with no pack is not offered",
    table.concat(Z:GetOfferedFallbackLanguages(nil), ","), "none,enUS,deDE")
Expect("A2. ...except the one the player has stored, which must stay visible",
    table.concat(Z:GetOfferedFallbackLanguages("koKR"), ","), "none,enUS,deDE,koKR")
Expect("A2. ...and a stored language that is still installed is not listed twice",
    table.concat(Z:GetOfferedFallbackLanguages("enUS"), ","), "none,enUS,deDE")
Expect("A2. ...nor None, which is the picker's own entry",
    table.concat(Z:GetOfferedFallbackLanguages("none"), ","), "none,enUS,deDE")
Expect("A2. a player with no packs is offered nothing but None",
    table.concat(Install({}):GetOfferedFallbackLanguages(nil), ","), "none")
-- A pack installed but switched off is still a pack the player has, so its language stays
-- offered; the pack list is where that fault gets reported.
local disabled = Pack("SpokenZonesAudio_deDE", "deDE", {})
disabled.enabled = false
Z = Install({ ENGLISH, disabled })
Expect("A2. an installed pack is offered however it turned out",
    table.concat(Z:GetOfferedFallbackLanguages(nil), ","), "none,enUS,deDE")

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
-- Every pack is named in its own language. A dropdown lists Français beside Español, and
-- one entry reading "ruRU" is the entry the player cannot read -- standing for the pack
-- they installed. A code is a folder; the endonym is the name of the thing they bought.
local RUSSIAN = Pack("SpokenZonesAudio_ruRU", "ruRU", {})
Z = Install({ ENGLISH, GERMAN, RUSSIAN })
Expect("E. a pack is named in its own language, not by its code",
    Z:GetAudioPackLabel(RUSSIAN), "Русский")
Expect("E. ...like every other language in the list", Z:GetAudioPackLabel(GERMAN), "Deutsch")

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

---------------------------------------------------------------- G. every finished language is offered
-- There was a font gate here once: it refused any language whose script differed from
-- the client's, on an inference from the client locale, because the client exposes no
-- way to ask which glyphs its fonts carry. It hid Russian, Korean and both Chineses
-- from clients that draw every one of them. A language a player can read is theirs to
-- try; a language they can never pick is one they can never report as missing.
local ALL_READY = {}
for _, code in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }) do
    table.insert(ALL_READY, { code = code, ready = true })
end
local function InstallEverywhere(locale, languages)
    stub.SetLocale(locale)
    _G.SpokenZonesDB = {}
    _G.SpokenZonesAudioPacks = {}
    return H.LoadZones(ZONES, { Languages = languages or ALL_READY })
end

local function codes(list)
    local out = {}
    for _, locale in ipairs(list) do table.insert(out, locale.code) end
    return table.concat(out, ",")
end

Z = InstallEverywhere("esES")
Expect("G. a Latin client is offered Russian", Z:IsLanguageSelectable("ruRU"), true)
Expect("G. ...and Korean", Z:IsLanguageSelectable("koKR"), true)
Expect("G. ...and Simplified Chinese", Z:IsLanguageSelectable("zhCN"), true)
Expect("G. ...and Traditional Chinese", Z:IsLanguageSelectable("zhTW"), true)
Expect("G. ...and every language, not just the ones near the client's own",
    codes(Z:GetSelectableLanguages()),
    "enUS,deDE,esES,esMX,frFR,ptBR,ruRU,koKR,zhCN,zhTW")

-- The same list on a client whose own language is finished: the gate that used to
-- depend on the client locale is gone, so nothing changes for anyone.
Z = InstallEverywhere("ruRU")
Expect("G. a Russian client is offered the same ten", codes(Z:GetSelectableLanguages()),
    "enUS,deDE,esES,esMX,frFR,ptBR,ruRU,koKR,zhCN,zhTW")
Expect("G. ...and reads Russian without being asked", Z:GetLanguage(), "ruRU")

-- Readiness is still the only gate, which is the point: an unfinished language is
-- not offered, and /spz lang <code> force is how it gets looked at.
local PARTIAL = {}
for _, entry in ipairs(ALL_READY) do
    if entry.code ~= "zhTW" then table.insert(PARTIAL, entry) end
end
Z = InstallEverywhere("esES", PARTIAL)
Expect("G. an unfinished language is not offered", Z:IsLanguageSelectable("zhTW"), false)
Expect("G. ...and the others still are", codes(Z:GetSelectableLanguages()),
    "enUS,deDE,esES,esMX,frFR,ptBR,ruRU,koKR,zhCN")

stub.SetLocale("enUS")
stub.ResetAddOns()
if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll zones language tests passed")
