-- The zones addon's settings panel. It is a canvas of its own -- the addon has settings
-- that have nothing to do with the player, and must have them with the player absent --
-- but it is laid out by the same UI/Layout.lua every Spoken addon carries, so the panels
-- read alike. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local ZONES = here .. "/../../addons/SpokenZones/"
local Expect, Failures = H.Expecter(print)

stub.SetClient("11509"); stub.ResetSound(); stub.ResetTimers(); stub.ResetFrames()
local Z = H.NewZoneLore()
for _, file in ipairs({ "UI/Layout", "UI/Options" }) do
    assert(loadfile(ZONES .. file .. ".lua"))("SpokenZones", Z)
end
Z:SetupOptions()

Expect("the panel is registered as a settings category", stub.settingsCategories[1] ~= nil, true)
Expect("...under its own name", stub.settingsCategories[1] and stub.settingsCategories[1].name, "Spoken Zones")

-- The rows live in the scroller's content frame, not on the panel: the settings canvas
-- neither scrolls nor clips, so a panel with more rows than fit draws over the world.
local content = Z.optionsPanel.content
local rows, headings = {}, {}
for _, child in ipairs(content.children) do
    if child.layoutHeading then
        table.insert(headings, { y = child.layoutY, height = child.layoutHeight, text = child.text })
    elseif child.layoutHeight then
        table.insert(rows, { y = child.layoutY, height = child.layoutHeight, anchor = child.anchor and child.anchor.y })
    end
end

Expect("every section is there", table.getn(headings), 7)
local names = {}
for _, heading in ipairs(headings) do table.insert(names, heading.text) end
Expect("...in order", table.concat(names, "|"),
    "World map|Minimap|Narration|Language|Sound packs|Troubleshooting|Feedback")
Expect("and every setting", table.getn(rows) >= 13, true)

---------------------------------------------------------------- the two language pickers
-- Voice language and Fallback language, which is the whole of the Language section here and
-- the whole of it in SpokenQuests and SpokenBooks: a player who sets a voice language in one
-- addon looks for it in the same place in the others. The language the lore text itself is
-- read in has no row -- /spz lang is how that is changed, and Auto follows the client either
-- way -- so the section holds nothing a player of the other two addons cannot find.
local labels = {}
for _, child in ipairs(content.children) do
    if child.dropdownInit and child.layoutLabel then table.insert(labels, child.layoutLabel.text) end
end
Expect("the language pickers are the two all three addons name alike",
    table.concat(labels, "|"), "Voice language|Fallback language")

-- The fallback picker, with no pack installed. A language with no pack is a setting that can
-- only narrate silence, so offering it would be offering nothing: English is on the picker
-- only because it is what the setting already holds, which is the one exception the rule
-- makes everywhere -- a picker that cannot show what it is set to is a control in an
-- unknown state. This is what a player who has not installed a pack yet sees.
local function Picker(label)
    for _, child in ipairs(content.children) do
        if child.dropdownInit and child.layoutLabel and child.layoutLabel.text == label then
            return child
        end
    end
end
local function Entries(dropdown)
    local texts = {}
    for _, entry in ipairs(stub.OpenDropdown(dropdown)) do table.insert(texts, entry.text) end
    return table.concat(texts, "|")
end
local fallback = Picker("Fallback language")
Expect("the fallback picker is on the panel", fallback ~= nil, true)
Expect("...offering None, and no language a pack could speak", Entries(fallback),
    "None (stay silent)|English")
Expect("...reading as the English a fresh install holds", fallback.dropdownText, "English")
Expect("switching it off is possible", stub.PickDropdown(fallback, "None (stay silent)"), true)
Expect("...and stores what the audio path reads", Z:GetFallbackLanguage(), "none")
Expect("...so nothing is left to fall back to", Entries(fallback), "None (stay silent)")

-- The voice picker, likewise with no pack: Auto alone, named with the lore language that
-- would be played -- there being no pack to name another.
local voice = Picker("Voice language")
Expect("the voice picker is on the panel", voice ~= nil, true)
Expect("...offering Auto and no pack at all", Entries(voice), "Auto (English)")

local function Distinct(values)
    local seen, count = {}, 0
    for _, value in ipairs(values) do
        local key = string.format("%.1f", value)
        if not seen[key] then seen[key] = true; count = count + 1 end
    end
    return count
end

-- The same two invariants the player's panel holds to. An indented row is a row, so its
-- own spacing is measured the same way; only its left edge moves.
local gaps = {}
for index = 2, table.getn(rows) do
    local previous = rows[index - 1]
    local crossesHeading = false
    for _, heading in ipairs(headings) do
        if heading.y < previous.y and heading.y > rows[index].y then crossesHeading = true end
    end
    if not crossesHeading then
        table.insert(gaps, previous.y - rows[index].y - previous.height)
    end
end
Expect("every row sits the same distance below the one above it", Distinct(gaps), 1)

local headingGaps = {}
for _, heading in ipairs(headings) do
    local above
    for _, row in ipairs(rows) do
        if row.y > heading.y and (not above or row.y < above.y) then above = row end
    end
    if above then table.insert(headingGaps, above.y - heading.y - above.height) end
end
Expect("every section heading the same distance below the section above", Distinct(headingGaps), 1)

local escaped = 0
for _, row in ipairs(rows) do
    if row.anchor and (row.anchor > row.y or row.anchor < row.y - row.height) then escaped = escaped + 1 end
end
Expect("no control escapes the row it was given", escaped, 0)

-- Derived from the layout rather than written down, so adding a row cannot leave a
-- section below the reach of the scrollbar.
Expect("the scroller is told how tall the content grew", content.height > 500, true)

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll zones options tests passed")
