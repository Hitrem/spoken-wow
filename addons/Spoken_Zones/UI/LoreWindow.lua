-- SpokenZones -- the lore window, Lore of Azeroth: every place's story, to browse and listen to
-- anywhere.
--
-- Opened from the minimap menu, the Zones settings page or /spz window. Independent of
-- WorldMapFrame, so it works with the map closed.
--
-- A panel the way the game draws its own -- the spellbook, the character sheet: a portrait
-- frame with the map's icon in its corner, its title along the top and the game's close button
-- (PortraitFrameTemplate). On the left, in an inset, the places as a tree: Azeroth, its two
-- continents, each continent's zones, and the opened zone's areas, with a search box over it. On the right, the story on the
-- spellbook's parchment (UI/LorePage.lua).
--
-- Only one zone expands at a time, which caps the list at the zones plus one zone's areas, about a
-- hundred rows -- few enough that every row can be a real button. A search shows every match
-- instead, and is short by being a search.

local ADDON_NAME, SpokenZones = ...

local L = SpokenZones.L
local Art = SpokenZones.Art

local WINDOW_WIDTH = 920
local WINDOW_HEIGHT = 600
-- 560 with a list of 270: wider by as much as the list, so the page keeps its narrowest width.
local WINDOW_MIN_WIDTH = 635
local WINDOW_MIN_HEIGHT = 360
-- Room for the longest zone name in any language (Portuguese's Cordilheira das Torres de
-- Pedra) beside its count, found out of all and the share: 27/27 • 100%.
local LIST_WIDTH = 345
local ZONE_ROW = 24
local AREA_ROW = 20
local DEPTH_STEP = 14         -- each level in, under the one it belongs to
local SCROLL_STEP = 60
local GRABBER_SIZE = 16
local ICON = [[Interface\Icons\INV_Misc_Map_01]]

local GRABBER_UP = [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]]
local GRABBER_DOWN = [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down]]
local GRABBER_HIGHLIGHT = [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]]

local SMALLER_UP = [[Interface\Buttons\UI-Panel-SmallerButton-Up]]
local SMALLER_DOWN = [[Interface\Buttons\UI-Panel-SmallerButton-Down]]
local BIGGER_UP = [[Interface\Buttons\UI-Panel-BiggerButton-Up]]
local BIGGER_DOWN = [[Interface\Buttons\UI-Panel-BiggerButton-Down]]
local PANEL_HI = [[Interface\Buttons\UI-Panel-MinimizeButton-Highlight]]

local window, listScroll, listChild, searchBox, page
local resizer, minimizeButton, minimizeFrame
local minimized = false
local rows = {}
local expandedZone = nil
-- Azeroth and its continents start open, so the zones show; each opens and closes on its own.
local worldOpen = true
local continentOpen = { [1414] = true, [1415] = true }
local selection = nil -- { mapID = , key = nil|string }
-- Sorted once, as sortedZoneIDs is: the tree is rebuilt on every click and keystroke, and the
-- data under it is fixed for the session (a language change reloads the interface).
local sortedZoneIDs = nil
local zonesOfContinent = {}
local sortedSubzoneKeys = {}
local filter = ""

local SetMinimized

--------------------------------------------------------------------------------
-- Data ordering
--------------------------------------------------------------------------------

local function ZoneName(mapID)
	return SpokenZones:GetMapName(mapID) or (SpokenZones.Zones[mapID] and SpokenZones.Zones[mapID].name) or tostring(mapID)
end

-- The world, its two continents, and which continent each zone is on.
local WORLD = 947
local CONTINENTS = { 1414, 1415 } -- Kalimdor, the Eastern Kingdoms
-- Where the client cannot say (C_Map's parents), Classic's own map ids: Kalimdor's zones and
-- cities, then the Eastern Kingdoms'.
local KNOWN_CONTINENT = {}
for _, id in ipairs({ 1411, 1412, 1413, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447,
	1448, 1449, 1450, 1451, 1452, 1454, 1456, 1457 }) do KNOWN_CONTINENT[id] = 1414 end
for _, id in ipairs({ 1416, 1417, 1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425, 1426, 1427, 1428,
	1429, 1430, 1431, 1432, 1433, 1434, 1435, 1436, 1437, 1453, 1455, 1458 }) do KNOWN_CONTINENT[id] = 1415 end

-- The cities, each listed inside the zone around it rather than beside it. The game has each as a
-- zone of its own (its own map, under the continent), so the zone it stands in is read off the
-- world: Stormwind City, Orgrimmar and Darnassus lie in that zone's map alone, and Ironforge,
-- Undercity and Thunder Bluff are entered from it (the Gates of Ironforge are Dun Morogh's, the
-- Ruins of Lordaeron Tirisfal's, and Thunder Bluff's mesa rises over Mulgore's plain).
local CITY_IN = { [1453] = 1429, [1454] = 1411, [1455] = 1426, [1456] = 1412, [1457] = 1438, [1458] = 1420 }
SpokenZones.CityIn = CITY_IN

local function IsContinent(mapID)
	return mapID == 1414 or mapID == 1415
end

local continentCache = {}
--- The continent a zone is on: up the game's map tree until one is reached, else Classic's ids.
local function ContinentOf(mapID)
	local cached = continentCache[mapID]
	if cached ~= nil then return cached or nil end
	local found
	local current, steps = mapID, 0
	while current and steps < 8 and C_Map and C_Map.GetMapInfo do
		local info = C_Map.GetMapInfo(current)
		local parent = info and info.parentMapID
		if not parent or parent == 0 then break end
		if IsContinent(parent) then found = parent break end
		current, steps = parent, steps + 1
	end
	found = found or KNOWN_CONTINENT[mapID]
	continentCache[mapID] = found or false
	return found
end


local function ByName(a, b)
	local na, nb = ZoneName(a), ZoneName(b)
	if na == nb then return a < b end
	return na < nb
end

-- A map this client has never heard of: in the data for another client (Forever's 2482, 2521,
-- 2524, 2548 and 2652 on Era), it would sit loose under Azeroth, counted among its zones, and
-- lead nowhere. Only where C_Map can be asked, and only for a zone on no continent we know.
local function UnknownHere(mapID)
	if not (C_Map and C_Map.GetMapInfo) or ContinentOf(mapID) then return false end
	return C_Map.GetMapInfo(mapID) == nil
end

--- Every zone with a story, alphabetical: everything in the data but Azeroth, its continents and
--- maps this client has not got.
local function ZoneIDs()
	if sortedZoneIDs then
		return sortedZoneIDs
	end
	sortedZoneIDs = {}
	for mapID in pairs(SpokenZones.Zones) do
		if mapID ~= WORLD and not IsContinent(mapID) and not UnknownHere(mapID) then
			table.insert(sortedZoneIDs, mapID)
		end
	end
	-- Alphabetical by display name: uiMapID order is meaningless to a reader.
	table.sort(sortedZoneIDs, ByName)
	return sortedZoneIDs
end

--- The continents that have a story, alphabetical.
local function Continents()
	local list = {}
	for _, mapID in ipairs(CONTINENTS) do
		if SpokenZones.Zones[mapID] then table.insert(list, mapID) end
	end
	table.sort(list, ByName)
	return list
end

--- A continent's zones, alphabetical; nil for the zones on no continent the game names.
local function ZonesOf(continent)
	if zonesOfContinent[continent] then return zonesOfContinent[continent] end
	local list = {}
	for _, mapID in ipairs(ZoneIDs()) do
		if ContinentOf(mapID) == continent and not CITY_IN[mapID] then table.insert(list, mapID) end
	end
	zonesOfContinent[continent] = list
	return list
end

--- The cities inside the zone `mapID`, alphabetical.
local function CitiesIn(mapID)
	local list = {}
	for _, city in ipairs(ZoneIDs()) do
		if CITY_IN[city] == mapID then table.insert(list, city) end
	end
	return list
end

--- Open what holds `mapID`, so opening on a place shows it.
local function Reveal(mapID)
	worldOpen = true
	local continent = IsContinent(mapID) and mapID or ContinentOf(mapID)
	if continent then continentOpen[continent] = true end
end

-- Whether this is the Forever client, which knows its own maps (Mount Hyjal's, 2482).
local onForever
local function OnForever()
	if onForever == nil then
		onForever = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(2482) ~= nil or false
	end
	return onForever
end

local function SubzoneKeys(mapID)
	local tbl = SpokenZones.Subzones[mapID]
	if not tbl then
		return nil
	end
	if sortedSubzoneKeys[mapID] then return sortedSubzoneKeys[mapID] end
	-- Not the areas only Forever has (Data/ForeverAreas.lua) on another client, which can never
	-- report them: listed, they would never be found.
	local foreverOnly = not OnForever() and SpokenZones.ForeverOnlyAreas and SpokenZones.ForeverOnlyAreas[mapID] or {}
	local keys = {}
	for key in pairs(tbl) do
		if not foreverOnly[key] then table.insert(keys, key) end
	end
	table.sort(keys, function(a, b)
		return (tbl[a].name or a) < (tbl[b].name or b)
	end)
	sortedSubzoneKeys[mapID] = keys
	return keys
end

local function Matches(text)
	return filter == "" or (text and string.find(string.lower(text), filter, 1, true) ~= nil)
end

-- Whether this character has found a place (Discovery.lua), whatever Unlock Undiscovered Places
-- says: the counts and Discovered Only go by it. The one chosen counts as found.
local function Found(mapID, key)
	if selection and selection.mapID == mapID and (key == nil or selection.key == key) then return true end
	return SpokenZones:IsFound(mapID, key)
end

-- Whether a place can be opened: every place with Unlock Undiscovered Places on, otherwise only
-- those found. The rest are listed greyed out.
local function Discovered(mapID, key)
	return SpokenZones:ShowsUndiscovered() or Found(mapID, key)
end

--- Whether a place is locked for this character: not found yet, with Unlock Undiscovered Places
--- off. A continent is found through its zones; Azeroth always is. The page and the map's panel
--- say so in its place rather than tell its story.
function SpokenZones:IsLocked(mapID, key)
	if self:ShowsUndiscovered() or mapID == WORLD then return false end
	if not key and IsContinent(mapID) then
		for _, zone in ipairs(ZonesOf(mapID)) do
			if self:IsFound(zone) then return false end
		end
		return true
	end
	return not self:IsFound(mapID, key)
end

-- Discovered Only, the checkbox under the list: the places not found are left out of it.
local function OnlyFound()
	return SpokenZones:Get("loreDiscoveredOnly") == true
end

local function Missing(mapID)
	local entry = SpokenZones:GetLore(mapID)
	return not entry or SpokenZones:IsPending(entry)
end

-- One zone's rows: itself, and under it when it is open its city (a zone of its own, with its
-- own areas) and its areas; while searching, the ones that match. Nothing when neither it nor
-- anything inside matches the search. A zone stays open while its city is. A zone not yet
-- discovered is listed locked: greyed out, and it does not open.
local function ZoneRows(mapID, depth)
	if OnlyFound() and not Found(mapID) then return {} end
	local locked = not Discovered(mapID)
	local subKeys = SubzoneKeys(mapID)
	local zoneName = ZoneName(mapID)
	local open = (expandedZone == mapID or CITY_IN[expandedZone] == mapID) and not locked
	local cities = CitiesIn(mapID)
	local inside = {}
	local found = 0
	for _, city in ipairs(cities) do
		if Found(city) then found = found + 1 end
		if filter ~= "" or open then
			for _, row in ipairs(ZoneRows(city, depth + 1)) do table.insert(inside, row) end
		end
	end
	if subKeys then
		for _, key in ipairs(subKeys) do
			local isFound = Found(mapID, key)
			if isFound then found = found + 1 end
			local entry = SpokenZones.Subzones[mapID][key]
			local name = entry.name or key
			local shown = filter == "" and open or filter ~= "" and Matches(name)
			if shown and (isFound or not OnlyFound()) then
				table.insert(inside, { kind = "subzone", mapID = mapID, key = key, label = name, depth = depth + 1,
					missing = SpokenZones:IsPending(entry), locked = not Discovered(mapID, key) })
			end
		end
	end
	if filter ~= "" and not Matches(zoneName) and #inside == 0 then return {} end
	local rows = { { kind = "zone", mapID = mapID, label = zoneName, depth = depth,
		count = found, total = (subKeys and #subKeys or 0) + #cities,
		open = filter ~= "" and #inside > 0 or open,
		missing = Missing(mapID), locked = locked } }
	for _, row in ipairs(inside) do table.insert(rows, row) end
	return rows
end

-- Flatten the tree into display rows: Azeroth, each continent under it, each continent's zones
-- under that, and the expanded zone's areas. While searching, every match with what holds it,
-- opened to show it.
local function BuildRowList()
	local list = {}
	local function Add(rows) for _, row in ipairs(rows) do table.insert(list, row) end end
	local searching = filter ~= ""

	local continents = {}
	for _, continent in ipairs(Continents()) do
		-- A closed continent's zones are never shown, and its count comes from ZonesOf: only
		-- a search, which can open it, needs them built.
		local zones = {}
		if searching or continentOpen[continent] then
			for _, mapID in ipairs(ZonesOf(continent)) do
				local rows = ZoneRows(mapID, 2)
				for _, row in ipairs(rows) do table.insert(zones, row) end
			end
		end
		local name = ZoneName(continent)
		local found = 0
		for _, mapID in ipairs(ZonesOf(continent)) do
			if Found(mapID) then found = found + 1 end
		end
		-- A continent with none of its zones found yet is listed locked, and does not open; with
		-- Discovered Only it is left out. Found through its zones alone: finding Brill finds the
		-- Eastern Kingdoms.
		local unfound = found == 0 and not (selection and selection.mapID == continent)
		local locked = unfound and not SpokenZones:ShowsUndiscovered()
		if (not searching or Matches(name) or #zones > 0) and not (unfound and OnlyFound()) then
			table.insert(continents, { kind = "continent", mapID = continent, label = name, depth = 1,
				count = found, total = #ZonesOf(continent),
				open = searching and #zones > 0 or (not searching and continentOpen[continent] and not locked),
				missing = Missing(continent), zones = zones, locked = locked })
		end
	end
	-- Zones on neither continent with a story, under Azeroth after them.
	local listed = {}
	for _, continent in ipairs(Continents()) do listed[continent] = true end
	local loose = {}
	for _, mapID in ipairs(ZoneIDs()) do
		if not listed[ContinentOf(mapID) or 0] then
			for _, row in ipairs(ZoneRows(mapID, 1)) do table.insert(loose, row) end
		end
	end

	local worldName = ZoneName(WORLD)
	local any = #continents > 0 or #loose > 0
	if SpokenZones.Zones[WORLD] and (not searching or Matches(worldName) or any) then
		local open = searching and any or (not searching and worldOpen)
		table.insert(list, { kind = "world", mapID = WORLD, label = worldName, depth = 0,
			count = #Continents(), open = open, missing = Missing(WORLD) })
		if not open then return list end
	end
	for _, continent in ipairs(continents) do
		table.insert(list, continent)
		if continent.open then Add(continent.zones) end
	end
	Add(loose)
	return list
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local function ShowEntry()
	if not selection then
		page:Show({ title = L.LORE_PICK, text = L.LORE_WINDOW_EMPTY, empty = true })
		return
	end

	local mapID, key = selection.mapID, selection.key
	-- Chosen from elsewhere (the map's panel), a place not found yet: named, and no more.
	if SpokenZones:IsLocked(mapID, key) then
		local entry = key and SpokenZones.Subzones[mapID] and SpokenZones.Subzones[mapID][key]
		-- Where it sits, a click away: the zone for an area, the continent for a zone.
		local up = key and mapID or (IsContinent(mapID) and WORLD or ContinentOf(mapID) or WORLD)
		local line = string.format(L.IN_ZONE_FMT, ZoneName(up))
		page:Show({ title = entry and (entry.name or key) or ZoneName(mapID), subtitle = line,
			onSubtitle = up and function()
				selection = { mapID = up, key = nil }
				SpokenZones:RefreshLoreWindow()
			end or nil,
			text = L.NOT_DISCOVERED, missing = true })
		return
	end
	if key then
		local entry = SpokenZones.Subzones[mapID] and SpokenZones.Subzones[mapID][key]
		if entry then
			local name = entry.name or key
			local line = SpokenZones:PlaceLine(mapID, key)
			local back = function()
				selection = { mapID = mapID, key = nil }
				SpokenZones:RefreshLoreWindow()
			end
			if SpokenZones:IsPending(entry) then
				page:Show({ title = name, subtitle = line, onSubtitle = back,
					text = L.LORE_NOT_WRITTEN:format(name), missing = true, contribute = { mapID, name } })
				return
			end
			-- Rows are keyed by the canonical form already, so this needs no normalising --
			-- unlike the map panel, which starts from the name the client reports.
			page:Show({ title = name, subtitle = line, onSubtitle = back,
				text = entry.full or entry.short or "", audio = { mapID, key }, report = { mapID, key } })
			return
		end
	end

	local entry = SpokenZones:GetLore(mapID)
	local name = ZoneName(mapID)
	local subtitle, up = SpokenZones:PlaceLine(mapID)
	local onSubtitle = up and function()
		selection = { mapID = up, key = nil }
		SpokenZones:RefreshLoreWindow()
	end or nil
	if not entry or SpokenZones:IsPending(entry) then
		page:Show({ title = name, subtitle = subtitle, onSubtitle = onSubtitle, text = L.LORE_NOT_WRITTEN:format(name),
			missing = true, contribute = { mapID, nil } })
		return
	end
	page:Show({ title = name, subtitle = subtitle, onSubtitle = onSubtitle, text = entry.full or entry.short or "",
		audio = { mapID, nil }, report = { mapID, nil } })
end

local function Count(n, many, one) return n == 1 and one or string.format(many, n) end

--- The line under a place's name: where it sits and how many places it holds. Also returns the
--- map one level up, which a click on the line opens (nil for Azeroth).
function SpokenZones:PlaceLine(mapID, key)
	if key then return string.format(L.IN_ZONE_FMT, ZoneName(mapID)), mapID end
	if mapID == WORLD then
		return Count(#Continents(), L.CONTINENT_COUNT_FMT, L.CONTINENT_COUNT_ONE) .. ", "
			.. Count(#ZoneIDs(), L.ZONE_COUNT_FMT, L.ZONE_COUNT_ONE), nil
	elseif IsContinent(mapID) then
		return string.format(L.IN_ZONE_FMT, ZoneName(WORLD)) .. " · "
			.. Count(#ZonesOf(mapID), L.ZONE_COUNT_FMT, L.ZONE_COUNT_ONE), WORLD
	end
	local parent = CITY_IN[mapID] or ContinentOf(mapID) or WORLD
	local subKeys = SubzoneKeys(mapID)
	local line = string.format(L.IN_ZONE_FMT, ZoneName(parent))
	if subKeys then
		line = line .. " · " .. Count(#subKeys, L.SUBZONE_COUNT_FMT, L.SUBZONE_COUNT_ONE)
	end
	return line, parent
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

local function IsSelected(row)
	if not selection then
		return false
	end
	if row.kind == "subzone" then
		return selection.mapID == row.mapID and selection.key == row.key
	end
	return selection.mapID == row.mapID and selection.key == nil
end

local function OnRowClick(self)
	local row = self.row
	if not row or row.locked then
		return
	end
	-- While searching the list shows every match opened, whatever is open: a toggle would change
	-- nothing there, only leave the tree folded when the search is cleared. Choose, and no more.
	if filter ~= "" then
		selection = { mapID = row.mapID, key = row.kind == "subzone" and row.key or nil }
	elseif row.kind == "world" then
		-- Azeroth and each continent open and close on their own; a click also chooses them.
		worldOpen = not worldOpen
		selection = { mapID = row.mapID, key = nil }
	elseif row.kind == "continent" then
		continentOpen[row.mapID] = not continentOpen[row.mapID]
		selection = { mapID = row.mapID, key = nil }
	elseif row.kind == "zone" then
		-- Clicking a zone both chooses it and opens or closes its areas: one zone at a time. Not
		-- `open and nil or mapID`, which is mapID either way, so an open zone never closed.
		-- A city closes back to the zone around it, which stays open; that zone closes with it.
		if expandedZone == row.mapID or CITY_IN[expandedZone] == row.mapID then
			expandedZone = CITY_IN[row.mapID]
		else
			expandedZone = row.mapID
		end
		selection = { mapID = row.mapID, key = nil }
	else
		selection = { mapID = row.mapID, key = row.key }
	end
	SetMinimized(false)
	SpokenLayout.Sound("U_CHAT_SCROLL_BUTTON")
	SpokenZones:RefreshLoreWindow()
end

-- A row's light: the professions list's own, faint under the pointer and full when chosen, with a
-- gold edge on the chosen one. A flat wash where the client has not got it.
local function Light(row)
	local wash = row.wash
	if row.selected then
		wash:Show(); wash:SetAlpha(1); row.edge:Show()
	elseif row.over then
		wash:Show(); wash:SetAlpha(0.55); row.edge:Hide()
	else
		wash:Hide(); row.edge:Hide()
	end
end

local function AcquireRow(index)
	local row = rows[index]
	if row then
		return row
	end

	row = CreateFrame("Button", nil, listChild)

	row.wash = row:CreateTexture(nil, "BACKGROUND")
	row.wash:SetAllPoints()
	if not Art.Atlas(row.wash, "Professions_Recipe_Hover", false) then
		row.wash:SetColorTexture(1, 1, 1, 0.1)
	end
	row.wash:Hide()

	row.edge = row:CreateTexture(nil, "ARTWORK")
	row.edge:SetWidth(2)
	row.edge:SetPoint("TOPLEFT")
	row.edge:SetPoint("BOTTOMLEFT")
	row.edge:SetColorTexture(1, 0.82, 0, 0.9)
	row.edge:Hide()

	row.toggle = row:CreateTexture(nil, "ARTWORK")
	row.toggle:SetSize(14, 14)
	row.toggle:SetPoint("LEFT", row, "LEFT", 8, 0)

	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.label:SetJustifyH("LEFT")
	if row.label.SetWordWrap then row.label:SetWordWrap(false) end

	row.count = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.count:SetPoint("RIGHT", row, "RIGHT", -10, 0)
	row.count:SetJustifyH("RIGHT")

	-- A padlock where the count goes, on a place not yet discovered: the group finder's own, grey.
	-- None where the client has not got it; the grey name still says it.
	row.lock = row:CreateTexture(nil, "ARTWORK")
	row.lock:SetSize(10, 12)
	row.lock:SetPoint("RIGHT", row, "RIGHT", -10, 0)
	row.hasLock = Art.Atlas(row.lock, "LFG-lock", false)
	if row.lock.SetDesaturated then row.lock:SetDesaturated(true) end
	row.lock:SetAlpha(0.6)
	row.lock:Hide()

	row:SetScript("OnClick", OnRowClick)
	row:SetScript("OnEnter", function(self) self.over = not (self.row and self.row.locked); Light(self) end)
	row:SetScript("OnLeave", function(self) self.over = false; Light(self) end)

	rows[index] = row
	return row
end

local function RenderList()
	local list = BuildRowList()
	local y = 0
	for i, item in ipairs(list) do
		local row = AcquireRow(i)
		row.row = item
		local height = item.kind == "subzone" and AREA_ROW or ZONE_ROW
		row:SetHeight(height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -y)
		row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -y)
		y = y + height

		row.label:ClearAllPoints()
		-- Locked, the padlock in the count's place.
		local locked = item.locked and row.hasLock
		row.lock:SetShown(locked and true or false)
		row.count:SetShown(not locked)
		row.label:SetPoint("RIGHT", locked and row.lock or row.count, "LEFT", -6, 0)
		local indent = (item.depth or 0) * DEPTH_STEP
		if item.kind ~= "subzone" then
			row.label:SetFontObject("GameFontNormal")
			row.label:SetPoint("LEFT", row, "LEFT", 28 + indent, 0)
			row.toggle:ClearAllPoints()
			row.toggle:SetPoint("LEFT", row, "LEFT", 8 + indent, 0)
			-- The game's own plus and minus, for anything with something inside to open.
			-- Not where nothing inside would be listed: none found, with Discovered Only on.
			if (item.total or item.count) > 0 and not item.locked and not (OnlyFound() and item.count == 0) then
				row.toggle:SetTexture(item.open and [[Interface\Buttons\UI-MinusButton-Up]] or [[Interface\Buttons\UI-PlusButton-Up]])
				row.toggle:Show()
			else
				row.toggle:Hide()
			end
			-- Found out of all, and how much of it that is: 5/27 • 18%.
			if item.total and item.total > 0 then
				row.count:SetText(string.format("%d/%d • %d%%", item.count, item.total,
					math.floor(100 * item.count / item.total)))
			else
				row.count:SetText(item.count > 0 and item.count or "")
			end
			if item.locked then
				row.label:SetTextColor(0.42, 0.42, 0.42)
			elseif item.missing then
				row.label:SetTextColor(0.62, 0.55, 0.36)
			else
				row.label:SetTextColor(1, 0.82, 0)
			end
		else
			row.label:SetFontObject("GameFontHighlightSmall")
			row.label:SetPoint("LEFT", row, "LEFT", 36 + indent, 0)
			row.toggle:Hide()
			row.count:SetText("")
			-- A place with no story yet, greyed: still there to choose, and to write.
			-- One not yet discovered, darker still: listed, but it does not open.
			if item.locked then
				row.label:SetTextColor(0.32, 0.32, 0.32)
			elseif item.missing then
				row.label:SetTextColor(0.5, 0.5, 0.5)
			else
				row.label:SetTextColor(0.92, 0.92, 0.92)
			end
		end
		row.label:SetText(item.label)

		row.selected = IsSelected(item)
		Light(row)
		row:Show()
	end

	for i = #list + 1, #rows do
		rows[i]:Hide()
		rows[i].row = nil
	end

	listChild:SetHeight(math.max(y, 1))
	window.noMatch:SetShown(#list == 0)
	return list
end

-- Bring the selected row into view. Only used when opening the window: doing it on every refresh
-- would yank the list out from under a click.
local function ScrollToSelection(list)
	if not selection then
		return
	end
	local y = 0
	for _, item in ipairs(list) do
		local height = item.kind == "subzone" and AREA_ROW or ZONE_ROW
		if IsSelected(item) then
			local viewHeight = listScroll:GetHeight() or 0
			-- GetVerticalScrollRange is stale until the next layout pass, right after
			-- listChild:SetHeight, so derive the range instead.
			local range = math.max(0, (listChild:GetHeight() or 0) - viewHeight)
			local target = y - (viewHeight / 2) + (height / 2)
			listScroll:SetVerticalScroll(math.max(0, math.min(range, target)))
			return
		end
		y = y + height
	end
end

function SpokenZones:RefreshLoreWindow(scrollToSelection)
	if not window then
		return
	end
	local list = RenderList()
	if scrollToSelection then
		ScrollToSelection(list)
	end
	ShowEntry()
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

-- The list inset's margins inside the window, left and right.
local function ListMargins()
	if window and window.templated then
		return 6, 6
	end
	return 14, 12
end

-- Collapsed, the window is just the list, at the width it has beside the text: only the height
-- resizes, so collapsing never reflows the rows.
local function CollapsedWidth()
	local left, right = ListMargins()
	return LIST_WIDTH + left + right
end

local function ScreenMaxWidth()
	return math.floor((UIParent:GetWidth() or 1920) * 0.95)
end

local function ScreenMaxHeight()
	return math.floor((UIParent:GetHeight() or 1080) * 0.95)
end

local function ApplyResizeBounds()
	local maxW = minimized and CollapsedWidth() or ScreenMaxWidth()
	local maxH = ScreenMaxHeight()
	local minW = minimized and CollapsedWidth() or WINDOW_MIN_WIDTH
	local minH = WINDOW_MIN_HEIGHT
	if window.SetResizeBounds then
		window:SetResizeBounds(minW, minH, maxW, maxH)
	else
		window:SetMinResize(minW, minH)
		window:SetMaxResize(maxW, maxH)
	end
end

-- StartSizing does not hold the opposite corner still. Anchored at CENTER, that corner moves
-- away from the cursor every frame and the size runs to its bound.
local function PinTopLeft()
	local left, top = window:GetLeft(), window:GetTop()
	if not left or not top then
		return
	end
	window:ClearAllPoints()
	window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

-- Saved sizes are clamped on the way in: a size persisted by the runaway would otherwise
-- reopen at the bound for good.
local function SavedSize(key, min, max, fallback)
	local saved = SpokenZones:Get(key)
	if type(saved) ~= "number" or saved < min then
		return fallback
	end
	return math.min(saved, max)
end

local function ExpandedWidth()
	return SavedSize("loreWindowWidth", WINDOW_MIN_WIDTH, ScreenMaxWidth(), WINDOW_WIDTH)
end

local function SavedHeight()
	return SavedSize("loreWindowHeight", WINDOW_MIN_HEIGHT, ScreenMaxHeight(), WINDOW_HEIGHT)
end

local function SaveWindowSize()
	if not window then
		return
	end
	local width, height = window:GetSize()
	if not width or not height or width <= 0 or height <= 0 then
		return
	end
	SpokenZones:Set("loreWindowHeight", math.floor(height + 0.5))
	if not minimized then
		SpokenZones:Set("loreWindowWidth", math.floor(width + 0.5))
	end
end

local function SetCollapseArrow()
	if minimizeFrame then
		minimizeFrame.MaximizeButton:SetShown(minimized)
		minimizeFrame.MinimizeButton:SetShown(not minimized)
		return
	end
	if not minimizeButton then
		return
	end
	if minimized then
		minimizeButton:SetNormalTexture(BIGGER_UP)
		minimizeButton:SetPushedTexture(BIGGER_DOWN)
	else
		minimizeButton:SetNormalTexture(SMALLER_UP)
		minimizeButton:SetPushedTexture(SMALLER_DOWN)
	end
end

SetMinimized = function(want)
	if not window or want == minimized then
		return
	end
	minimized = want
	ApplyResizeBounds()
	PinTopLeft()
	window:SetWidth(minimized and CollapsedWidth() or ExpandedWidth())
	window.pageInset:SetShown(not minimized)
	SetCollapseArrow()
end

-- The game's portrait frame where the client has it: its border, title bar, portrait and close
-- button. The plain dialog box this window used to be where it does not.
local function NewWindow()
	local ok, frame = pcall(CreateFrame, "Frame", "SpokenZonesWindow", UIParent, "PortraitFrameTemplate")
	if ok and frame and frame.SetTitle then
		frame:SetTitle(L.LORE_WINDOW_TITLE)
		if frame.SetPortraitToAsset then frame:SetPortraitToAsset(ICON) end
		frame.templated = true
		return frame
	end
	frame = CreateFrame("Frame", "SpokenZonesWindow", UIParent, "BackdropTemplate")
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOP", frame, "TOP", 0, -14)
	title:SetText(L.LORE_WINDOW_TITLE)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -8)
	close:SetScript("OnClick", function() frame:Hide() end)
	frame.CloseButton = close
	return frame
end

local function BuildWindow()
	window = NewWindow()
	window:SetSize(ExpandedWidth(), SavedHeight())
	window:SetPoint("CENTER")
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:SetResizable(true)
	window:SetClampedToScreen(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetScript("OnShow", function()
		-- The screen may have changed size since the bounds were last set.
		ApplyResizeBounds()
		-- A place found since the window last opened is listed now.
		if SpokenZones.RefreshFound then SpokenZones:RefreshFound() end
		if PlaySound and SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN then PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN) end
	end)
	window:SetScript("OnHide", function()
		if PlaySound and SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_CLOSE then PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE) end
	end)
	window:Hide()

	local close = type(window.CloseButton) == "table" and window.CloseButton
	if close then
		local buttonSize = math.max((close:GetWidth() > 0 and close:GetWidth() or 32) - 2, 24)
		close:SetSize(buttonSize, buttonSize)
		close:ClearAllPoints()
		if window.templated then
			close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -1)
		else
			close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -10, -8)
		end

		local ok, mm = pcall(CreateFrame, "Frame", nil, window, "MaximizeMinimizeButtonFrameTemplate")
		if ok and mm and mm.MaximizeButton and mm.MinimizeButton then
			minimizeFrame = mm
			mm:ClearAllPoints()
			mm:SetPoint("RIGHT", close, "LEFT", 0, 0)
			mm:SetFrameLevel(close:GetFrameLevel())
			mm.MinimizeButton:SetSize(buttonSize, buttonSize)
			mm.MaximizeButton:SetSize(buttonSize, buttonSize)
			mm.MinimizeButton:SetScript("OnClick", function()
				SetMinimized(true)
			end)
			mm.MaximizeButton:SetScript("OnClick", function()
				SetMinimized(false)
				SpokenZones:RefreshLoreWindow()
			end)
		else
			minimizeButton = CreateFrame("Button", nil, window)
			minimizeButton:SetSize(buttonSize, buttonSize)
			minimizeButton:SetPoint("RIGHT", close, "LEFT", 0, 0)
			minimizeButton:SetFrameLevel(close:GetFrameLevel())
			minimizeButton:SetHighlightTexture(PANEL_HI)
			minimizeButton:SetScript("OnClick", function()
				SetMinimized(not minimized)
				if not minimized then SpokenZones:RefreshLoreWindow() end
			end)
		end
		SetCollapseArrow()
	end

	-- Inside the frame's border and under its title bar; a templated frame's portrait takes the
	-- top-left corner, so the search box starts to its right.
	local top = window.templated and -24 or -36
	local left, right = ListMargins()

	-- The places: an inset down the left, the game's own, with the search box over it.
	searchBox = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
	searchBox:SetSize(LIST_WIDTH - 66, 20)
	searchBox:SetPoint("TOPLEFT", window, "TOPLEFT", left + 66, top - 8)
	if type(searchBox.Instructions) == "table" then searchBox.Instructions:SetText(L.LORE_SEARCH) end
	searchBox:HookScript("OnTextChanged", function(self)
		filter = string.lower(strtrim and strtrim(self:GetText() or "") or (self:GetText() or ""))
		listScroll:SetVerticalScroll(0)
		SpokenZones:RefreshLoreWindow()
	end)

	local ok, inset = pcall(CreateFrame, "Frame", nil, window, "InsetFrameTemplate")
	if not ok or not inset then inset = CreateFrame("Frame", nil, window) end
	inset:SetPoint("TOPLEFT", window, "TOPLEFT", left, top - 38)
	inset:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", left, 30)
	inset:SetWidth(LIST_WIDTH)
	window.inset = inset

	listScroll = CreateFrame("ScrollFrame", nil, inset)
	listScroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
	listScroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
	if listScroll.SetClipsChildren then
		listScroll:SetClipsChildren(true)
	end
	listScroll:EnableMouseWheel(true)
	listScroll:SetScript("OnMouseWheel", function(self, delta)
		local range = math.max(0, (listChild:GetHeight() or 0) - (self:GetHeight() or 0))
		local target = self:GetVerticalScroll() - (delta * SCROLL_STEP)
		self:SetVerticalScroll(math.max(0, math.min(range, target)))
	end)

	listChild = CreateFrame("Frame", nil, listScroll)
	listChild:SetSize(LIST_WIDTH - 8, 1)
	listScroll:SetScrollChild(listChild)
	-- The page's scroll bar, the game's minimal one, down the list's right side.
	window.listBar = SpokenZones:AddScrollBar(listScroll, listChild, inset)

	-- Discovered Only, under the list: leaves out the places this character has not found.
	local okOnly, only = pcall(CreateFrame, "CheckButton", nil, window, "UICheckButtonTemplate")
	if okOnly and only then
		only:SetSize(24, 24)
		only:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", left, 4)
		local text = only.text or only.Text
		if not (text and text.SetFontObject) then text = only:CreateFontString(nil, "ARTWORK") end
		text:SetFontObject("GameFontHighlightSmall")
		text:ClearAllPoints()
		text:SetPoint("LEFT", only, "RIGHT", 2, 0)
		text:SetText(L.LORE_DISCOVERED_ONLY)
		only.label = text
		only:SetChecked(OnlyFound())
		only:SetScript("OnClick", function(self)
			SpokenZones:Set("loreDiscoveredOnly", self:GetChecked() and true or false)
			listScroll:SetVerticalScroll(0)
			SpokenZones:RefreshLoreWindow()
		end)
		window.discoveredOnly = only
	end

	window.noMatch = inset:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	window.noMatch:SetPoint("TOP", inset, "TOP", 0, -24)
	window.noMatch:SetText(L.LORE_SEARCH_NONE)
	window.noMatch:Hide()

	-- The story: the spellbook's page down the rest of the window, in an inset of its own as the
	-- list is -- the way the game's split windows frame each pane (the professions window), so the
	-- two are parted by their borders rather than one running into the other.
	local okPage, pageInset = pcall(CreateFrame, "Frame", nil, window, "InsetFrameTemplate")
	if not okPage or not pageInset then pageInset = CreateFrame("Frame", nil, window) end
	pageInset:SetPoint("TOPLEFT", inset, "TOPRIGHT", 6, 38)
	pageInset:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -right, window.templated and 6 or 12)
	window.pageInset = pageInset
	local holder = CreateFrame("Frame", nil, pageInset)
	holder:SetPoint("TOPLEFT", pageInset, "TOPLEFT", 3, -3)
	holder:SetPoint("BOTTOMRIGHT", pageInset, "BOTTOMRIGHT", -3, 3)
	page = SpokenZones:CreateLorePage(holder, "book")
	-- The inset's border over the parchment's edge, not under it.
	if type(pageInset.NineSlice) == "table" and pageInset.NineSlice.SetFrameLevel then
		pageInset.NineSlice:SetFrameLevel(holder:GetFrameLevel() + 5)
	end
	window.page = page

	resizer = CreateFrame("Button", nil, window)
	resizer:SetPoint("BOTTOMRIGHT", -2, 2)
	resizer:SetSize(GRABBER_SIZE, GRABBER_SIZE)
	resizer:SetNormalTexture(GRABBER_UP)
	resizer:SetPushedTexture(GRABBER_DOWN)
	resizer:SetHighlightTexture(GRABBER_HIGHLIGHT)
	resizer:SetFrameLevel(window:GetFrameLevel() + 5)
	resizer:SetScript("OnEnter", function()
		SetCursor([[Interface\Cursor\UI-Cursor-SizeRight]])
	end)
	resizer:SetScript("OnLeave", function()
		SetCursor(nil)
	end)
	resizer:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then
			return
		end
		local highlight = resizer:GetHighlightTexture()
		if highlight then
			highlight:Hide()
		end
		PinTopLeft()
		window:StartSizing("BOTTOMRIGHT")
	end)
	resizer:SetScript("OnMouseUp", function()
		local highlight = resizer:GetHighlightTexture()
		if highlight then
			highlight:Show()
		end
		window:StopMovingOrSizing()
		SaveWindowSize()
		SetCursor(nil)
	end)

	-- Toggling "Hide Contribute Buttons" in Spoken's settings fires no game event.
	if _G.Spoken and Spoken.RegisterCallback then
		Spoken:RegisterCallback("CONTRIBUTE_SETTINGS_CHANGED", function()
			SpokenZones:RefreshLoreWindow()
		end)
	end

	SpokenZones.window = window
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

-- The zone the player is standing in, resolved to something we actually have lore for.
-- C_Map.GetBestMapForUnit can return an indoor or micro map (an inn, a dungeon) that is not
-- itself a key in Zones, so walk up to its parent.
local function CurrentZoneID()
	local playerMap = SpokenZones:GetPlayerMapID()
	if not playerMap then
		return nil
	end
	local _, resolved = SpokenZones:GetLoreWithFallback(playerMap)
	return resolved
end

--- Close the lore window, as switching the part off does.
function SpokenZones:HideLoreWindow()
	if window then
		window:Hide()
	end
end

function SpokenZones:ToggleLoreWindow()
	if not window then
		return
	end
	if window:IsShown() then
		window:Hide()
		return
	end

	-- Re-sync to where the player is standing on every open, not just the first: opening from the
	-- minimap should land on the current zone, not wherever the last browse ended.
	local current = CurrentZoneID()
	if current then
		-- Standing in an area with lore of its own is more specific than the zone, so prefer it.
		-- Either way the zone is opened.
		local subZone = GetSubZoneText()
		local subEntry, subKey
		if subZone and subZone ~= "" then
			subEntry, subKey = SpokenZones:GetSubzoneLore(current, subZone)
		end
		expandedZone = current
		Reveal(current)
		selection = { mapID = current, key = subEntry and subKey or nil }
	end

	if searchBox and searchBox:GetText() ~= "" then searchBox:SetText("") end
	window:Show()
	SpokenZones:RefreshLoreWindow(true)
end

-- Open on a named entry rather than on the player's location. Not routed through
-- ToggleLoreWindow, which re-syncs to where the player stands: narration outlives the zone you
-- started it in.
function SpokenZones:ShowLoreFor(mapID, areaKey)
	if not window or not mapID then
		return
	end
	expandedZone = mapID
	Reveal(mapID)
	selection = { mapID = mapID, key = areaKey }
	if searchBox and searchBox:GetText() ~= "" then searchBox:SetText("") end
	window:Show()
	-- Asked for an entry, so show it: a window closed collapsed would reopen as the bare list.
	SetMinimized(false)
	SpokenZones:RefreshLoreWindow(true)
end

function SpokenZones:SetupLoreWindow()
	if window then
		return
	end
	BuildWindow()
	tinsert(UISpecialFrames, "SpokenZonesWindow") -- close on Escape
end
