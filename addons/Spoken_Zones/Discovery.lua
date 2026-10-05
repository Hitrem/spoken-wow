-- SpokenZones -- which places this character has found, for Lore of Azeroth's list.
--
-- Lore of Azeroth lists only the places found, with their count out of all, unless the player
-- turns on Show Undiscovered Places. A place counts as found when either:
--
--   * the client has it explored. Every explored area is drawn on its zone's map as an
--     exploration overlay, and asking which explored areas lie under those overlays
--     (C_MapExplorationInfo.GetExploredAreaIDsAtPosition) names them. That covers everything
--     explored before Spoken Zones was installed.
--   * the character has stood in it since. Small places and the cities' districts have no
--     overlay and never count as explored, so every zone change records where the character is
--     (SpokenZonesCharacter.visited).
--
-- A zone is found when it, or any of its areas, is; a city also when its name is explored on
-- the zone around it (Orgrimmar on Durotar's map). The map scan is done once per zone a session,
-- and the zone the character is in is scanned again whenever the list is drawn, so a discovery
-- shows the next time Lore of Azeroth is opened.

local ADDON_NAME, SpokenZones = ...

-- Points asked about across each overlay's rectangle, this many a side: an overlay's rectangle
-- can hold a smaller area of its own, which only some points land in.
local SAMPLES = 4

local explored = {}       -- [mapID] = { zone = bool, keys = { [areaKey] = true } }, this session
local exploredNames = {}  -- every explored area's name seen in a scan, for the cities

local function CharDB()
	if type(SpokenZonesCharacter) ~= "table" then
		SpokenZonesCharacter = {}
	end
	if type(SpokenZonesCharacter.visited) ~= "table" then
		SpokenZonesCharacter.visited = {}
	end
	return SpokenZonesCharacter
end

local function VisitKey(mapID, areaKey)
	return areaKey and (mapID .. "/" .. areaKey) or tostring(mapID)
end

--- The explored areas on the map `mapID`, read off its overlays.
local function Scan(mapID)
	local result = { zone = false, keys = {} }
	explored[mapID] = result
	local info = C_MapExplorationInfo
	if not (info and info.GetExploredMapTextures and info.GetExploredAreaIDsAtPosition and C_Map.GetMapArtLayers) then
		return result
	end
	local ok, overlays = pcall(info.GetExploredMapTextures, mapID)
	local layers = C_Map.GetMapArtLayers(mapID)
	local layer = layers and layers[1]
	if not ok or not overlays or not layer or layer.layerWidth == 0 then
		return result
	end
	result.zone = #overlays > 0
	for _, overlay in ipairs(overlays) do
		local r = overlay.hitRect
		if r then
			local scaleX, scaleY = 1 / layer.layerWidth, 1 / layer.layerHeight
			if r.right <= 1 and r.bottom <= 1 then scaleX, scaleY = 1, 1 end
			for i = 1, SAMPLES do
				for j = 1, SAMPLES do
					local x = (r.left + (r.right - r.left) * (i - 0.5) / SAMPLES) * scaleX
					local y = (r.top + (r.bottom - r.top) * (j - 0.5) / SAMPLES) * scaleY
					local okAt, ids = pcall(info.GetExploredAreaIDsAtPosition, mapID, CreateVector2D(x, y))
					for _, areaID in ipairs(okAt and ids or {}) do
						local name = C_Map.GetAreaInfo(areaID)
						if name then
							exploredNames[name] = true
							local key = SpokenZones:ResolveAreaKey(name)
							if key then result.keys[key] = true end
						end
					end
				end
			end
		end
	end
	return result
end

local function Explored(mapID)
	return explored[mapID] or Scan(mapID)
end

-- Every zone's map read, so a city is known explored by its name on the zone around it whichever
-- is asked about first (Darnassus sorts before Teldrassil). Once a session.
local everyZone = false
local function ScanEveryZone()
	if everyZone then return end
	everyZone = true
	for mapID in pairs(SpokenZones.Zones or {}) do
		Explored(mapID)
	end
end

--- Scan the zone the character is in again, so a discovery made since shows.
function SpokenZones:RefreshFound()
	local _, mapID = self:GetLoreWithFallback(self:GetPlayerMapID())
	if mapID then Scan(mapID) end
end

--- Whether the character has found the zone `mapID` (areaKey nil) or its area `areaKey`.
function SpokenZones:IsFound(mapID, areaKey)
	if not mapID then
		return false
	end
	local visited = CharDB().visited
	if areaKey then
		return visited[VisitKey(mapID, areaKey)] == true or Explored(mapID).keys[areaKey] == true
	end
	if visited[VisitKey(mapID)] or Explored(mapID).zone or next(Explored(mapID).keys) then
		return true
	end
	ScanEveryZone()
	local name = self:GetMapName(mapID)
	if name and exploredNames[name] then
		return true
	end
	for key in pairs(self.Subzones[mapID] or {}) do
		if visited[VisitKey(mapID, key)] then return true end
	end
	return false
end

--- Whether Lore of Azeroth lists every place or only those found.
function SpokenZones:ShowsUndiscovered()
	return self:Get("showUndiscovered") == true
end

-- Where the character stands, recorded on every zone change.
local function RecordVisit()
	local _, mapID = SpokenZones:GetLoreWithFallback(SpokenZones:GetPlayerMapID())
	if not mapID then
		return
	end
	local visited = CharDB().visited
	visited[VisitKey(mapID)] = true
	local subZone = GetSubZoneText and GetSubZoneText()
	if subZone and subZone ~= "" then
		local _, key = SpokenZones:GetSubzoneLore(mapID, subZone)
		if key then visited[VisitKey(mapID, key)] = true end
	end
end

function SpokenZones:SetupDiscovery()
	self:OnZoneChanged(RecordVisit)
end
