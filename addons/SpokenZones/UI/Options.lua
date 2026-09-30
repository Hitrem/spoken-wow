-- SpokenZones -- options panel in the interface settings.
--
-- Registered with Settings.RegisterCanvasLayoutCategory, which exists on 11509
-- (Leatrix_Maps, Leatrix_Plus, Leatrix_Sounds, Syndicator and Baganator all use
-- it). InterfaceOptions_AddCategory is the legacy-only path and is not used.
--
-- Widget templates are picked from what addons already running on this client
-- use: UICheckButtonTemplate (Syndicator/Options) and UISliderTemplate
-- (Syndicator/Options, Leatrix_Maps, Leatrix_Plus).

local ADDON_NAME, SpokenZones = ...

local L = SpokenZones.L

local INDENT = 20

local panel, category

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local function MakeHeading(parent, text, x, y, template)
	local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormalLarge")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

--------------------------------------------------------------------------------
-- Apply helpers
--------------------------------------------------------------------------------

local function RedrawPanel()
	if SpokenZones.ApplyPanelOptions then
		SpokenZones:ApplyPanelOptions()
	end
end

local function RedrawEverything()
	RedrawPanel()
	if SpokenZones.RefreshLoreWindow then
		SpokenZones:RefreshLoreWindow()
	end
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

function SpokenZones:SetupOptions()
	if panel then
		return
	end

	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		SpokenZones:Print("|cffffcc00Settings API missing; options panel unavailable (use /spz help)|r")
		return
	end

	-- Parentless, with `.name` set, is the shape the Settings API expects here.
	panel = CreateFrame("Frame")
	panel.name = "Spoken Zones"

	-- Everything below is laid out in `content`, not in `panel`. The settings canvas
	-- is a fixed size and neither scrolls nor clips what overflows it, so a panel
	-- with more rows than fit draws them over the game world. See UI/Scroller.lua.
	local scroller = SpokenLayout.Scroll(panel)
	local content = scroller.child
	panel.content = content

	MakeHeading(content, "Spoken Zones", INDENT, -16)
	local layout = SpokenLayout.New(content, INDENT, -42)
	layout:Note(L.OPT_NOTE)

	-- Every row's position, and the spacing between them, comes from UI/Layout.lua -- the
	-- file every Spoken addon carries a copy of, so the three panels read alike.
	local function Get(key) return function() return SpokenZones:Get(key) end end
	local function Set(key) return function(value) SpokenZones:Set(key, value) end end

	layout:Section(L.OPT_SECTION_MAP)
	layout:Checkbox(L.OPT_MAP_PANEL,
		L.OPT_MAP_PANEL_TIP,
		Get("showMapPanel"), Set("showMapPanel"), RedrawPanel)
	layout:Checkbox(L.OPT_HOVER,
		L.OPT_HOVER_TIP,
		Get("showHoverPreview"), Set("showHoverPreview"))
	-- Stored as a string ("LEFT"/"RIGHT") rather than a boolean, so it reads and writes
	-- its own way rather than through Get/Set above.
	layout:Checkbox(L.OPT_PANEL_LEFT, nil,
		function() return SpokenZones:Get("panelSide") == "LEFT" end,
		function(value) SpokenZones:Set("panelSide", value and "LEFT" or "RIGHT") end,
		RedrawPanel)
	layout:Slider(L.OPT_PANEL_WIDTH, 220, 520, 10,
		Get("panelWidth"), Set("panelWidth"), RedrawPanel, SpokenLayout.Number)
	layout:Slider(L.OPT_FONT_SIZE, 9, 20, 1,
		Get("fontSize"), Set("fontSize"), RedrawEverything, SpokenLayout.Number)

	layout:Section(L.OPT_SECTION_MINIMAP)
	layout:Checkbox(L.OPT_MINIMAP_BUTTON,
		L.OPT_MINIMAP_BUTTON_TIP,
		Get("showMinimapButton"), Set("showMinimapButton"), function()
			-- The checkbox has already written the option, so sync rather than
			-- toggle; ApplyMinimapButton also keeps `hide` in step for LibDBIcon.
			if SpokenZones.ApplyMinimapButton then
				SpokenZones:ApplyMinimapButton()
			end
		end)

	layout:Section(L.OPT_SECTION_NARRATION)
	layout:Checkbox(L.OPT_PLAY_BUTTON,
		L.OPT_PLAY_BUTTON_TIP,
		Get("voiceEnabled"), Set("voiceEnabled"), function()
			SpokenZones:StopLore()
			SpokenZones:NotifyAudioChanged()
		end)
	layout:Checkbox(L.OPT_AUTOPLAY,
		L.OPT_AUTOPLAY_TIP,
		Get("autoplay"), Set("autoplay"), function()
			if not SpokenZones:Get("autoplay") then
				SpokenZones:StopLore()
			end
		end)
	layout:Indent()
	layout:Checkbox(L.OPT_AUTOPLAY_SUB,
		L.OPT_AUTOPLAY_SUB_TIP,
		Get("autoplaySubzones"), Set("autoplaySubzones"))
	layout:Checkbox(L.OPT_AUTOPLAY_EXPLORED,
		L.OPT_AUTOPLAY_EXPLORED_TIP,
		Get("autoplayExplored"), Set("autoplayExplored"))
	layout:Outdent()

	-- The picker's own Auto entry. A table rather than a code because the values beside it
	-- are packs, not languages, and there is no language code that means "let the addon
	-- decide"; the stored absence of a preference is what Auto means.
	local AUTO = {}

	-- Voice language then fallback language, which is the whole of this section and the
	-- whole of the Language section in SpokenQuests and SpokenBooks. A player who sets a
	-- voice language in one addon looks for it in the same place in the others.
	layout:Section(L.OPT_SECTION_LANGUAGE)
	-- The list is read when the menu opens rather than captured here: packs cannot be
	-- installed mid-session, but a player who disables one in the AddOns list and reloads
	-- should not find this offering it.
	local function PackLabel(pack)
		if pack ~= AUTO then
			return SpokenZones:GetAudioPackLabel(pack)
		end
		-- Named with the language Auto would actually play, which is the one being read
		-- whenever a pack in it is installed and the client's own when none is.
		local active = SpokenZones:GetActiveAudioPack()
		return string.format(L.OPT_LANG_AUTO_FMT,
			SpokenZones:GetLanguageName(active and active.language or SpokenZones:GetLanguage()))
	end
	layout:Dropdown(L.OPT_VOICE_LANGUAGE, L.OPT_VOICE_LANGUAGE_TIP,
		function()
			local values = { AUTO }
			for _, pack in ipairs(SpokenZones:GetAudioPacks()) do
				table.insert(values, pack)
			end
			return values
		end,
		-- No stored preference is Auto, which is what makes Auto the entry a player comes
		-- back to: until now, having once chosen a pack, there was no way to hand it back.
		function() return SpokenZones:GetPreferredAudioPack() or AUTO end,
		function(pack)
			SpokenZones:SetActiveAudioPack(pack == AUTO and nil or pack.addon)
		end,
		nil,
		PackLabel)

	-- Only the languages an installed pack speaks: a language with no pack is a setting
	-- that can only narrate silence, so offering it would be offering nothing. None is the
	-- first entry because it is a choice in its own right, and the one a player who wants
	-- only their own language makes.
	layout:Dropdown(L.OPT_FALLBACK_LANGUAGE, L.OPT_FALLBACK_LANGUAGE_TIP,
		function()
			return SpokenZones:GetOfferedFallbackLanguages(SpokenZones:GetFallbackLanguage())
		end,
		function() return SpokenZones:GetFallbackLanguage() end,
		function(code) SpokenZones:SetFallbackLanguage(code) end,
		nil,
		function(code)
			return code == "none" and L.OPT_FALLBACK_NONE or SpokenZones:GetLanguageName(code)
		end)

	-- The packs, in their own section. "Which pack is this" used to be a note under the
	-- voice picker; a list that answers "is my audio installed, and which version" does
	-- the job, and it is where SpokenQuests puts the same answer -- name and version a
	-- row, so a player can check an install without reading a second window.
	layout:Section(L.OPT_SECTION_PACKS)
	local packRows = {}
	local function DescribePacks()
		local packs = SpokenZones:GetAudioPacks()
		for index, pack in ipairs(packs) do
			local row = packRows[index]
			if row then
				row.note:SetText(("%s  |cff888888%s|r"):format(
					SpokenZones:GetAudioPackLabel(pack), pack.packVersion or ""))
				row.note:Show()
			end
		end
		for index = #packs + 1, table.getn(packRows) do
			packRows[index].note:Hide()
		end
		if #packs == 0 and packRows[1] then
			packRows[1].note:SetText(L.OPT_PACK_NONE)
			packRows[1].note:Show()
		end
	end
	-- A row apiece, built once: the set of installed packs cannot change mid-session, and
	-- the panel is built after they have all loaded. One row even with none, so the
	-- "install one" note has somewhere to live.
	local packCount = #SpokenZones:GetAudioPacks()
	for index = 1, math.max(packCount, 1) do
		packRows[index] = { note = layout:Note("", 460, 16) }
	end
	DescribePacks()
	content:SetScript("OnShow", DescribePacks)

	layout:Section(L.OPT_SECTION_TROUBLE)
	layout:Checkbox(L.OPT_DEBUG_MAP_CLICK,
		L.OPT_DEBUG_MAP_CLICK_TIP,
		Get("debug"), Set("debug"))

	-- Its own section rather than part of Troubleshooting, and not only because the
	-- checkbox above already uses the word "report": the per-line Report buttons
	-- cover a bad line, and this covers everything that belongs to no line at all --
	-- the addon erroring, the voice being wrong throughout, the site itself.
	layout:Section(L.OPT_SECTION_FEEDBACK)
	layout:Button(L.OPT_REPORT_PROBLEM, 220, function()
		SpokenZones:ShowCopyLink(SpokenZones.SITE_URL,
			L.OPT_REPORT_ADDRESS)
	end)
	layout:Note(L.OPT_REPORT_NOTE, 460, 40)

	-- Derived rather than written as a number: a hardcoded height is a number nobody
	-- updates when a row is added, and the failure it produces is the one this scroller
	-- exists to fix -- a section you cannot reach.
	scroller:SetContentHeight(layout:Height() + 40)

	category = Settings.RegisterCanvasLayoutCategory(panel, "Spoken Zones")
	Settings.RegisterAddOnCategory(category)

	SpokenZones.optionsPanel = panel
	SpokenZones.optionsCategory = category
end

function SpokenZones:OpenOptions()
	if not category or not (Settings and Settings.OpenToCategory) then
		SpokenZones:Print("open Game Menu -> Options -> AddOns -> Spoken Zones")
		return
	end

	-- OpenToCategory takes an ID in some builds and the category object in others,
	-- so try the ID first and fall back rather than erroring.
	local id = category.GetID and category:GetID() or nil
	local ok = id and pcall(Settings.OpenToCategory, id)
	if not ok then
		ok = pcall(Settings.OpenToCategory, category)
	end
	if not ok then
		SpokenZones:Print("open Game Menu -> Options -> AddOns -> Spoken Zones")
	end
end
