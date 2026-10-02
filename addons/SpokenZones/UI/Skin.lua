-- SpokenZones -- the look the map panel and the lore window share.
--
-- Where the world map wears the modern metal frame (Forever builds its map from
-- PortraitFrameTemplateMinimizable), the panel and the window wear the same metal,
-- through the client's own NineSlice layout, so the panel's edges continue the map's.
-- Forever's metal art is bronze already; nothing is tinted here.
--
-- Elsewhere they keep the dialog border. Either way the background is the dark rock
-- the Spoken player's minimal skin wears (SpokenPlayer/UI/MinimalPlayer.lua). The
-- texture is a copy rather than a path into SpokenPlayer: that addon is only an
-- optional dependency, and a missing texture draws as solid green.

local ADDON_NAME, SpokenZones = ...

local ROCK = "Interface\\AddOns\\SpokenZones\\Textures\\FrameBackground"
local TILE = 256

-- The portrait-less sibling of the map's layout: same atlases, same top and bottom
-- offsets, so two frames of equal height line up edge for edge.
local METAL_LAYOUT = "ButtonFrameTemplateNoPortrait"
-- Where PortraitFrameTexturedBaseTemplate lays its background: under the title bar
-- the metal's top edge draws, and inside its thin sides.
local METAL_INSETS = { left = 2, right = 2, top = 21, bottom = 2 }
local DIALOG_INSETS = { left = 11, right = 12, top = 12, bottom = 11 }

-- Decided on first use rather than at load: WorldMapFrame may not exist yet then.
local metal
function SpokenZones:UsesMetalFrames()
	if metal == nil then
		local map = _G.WorldMapFrame
		metal = (map and map.BorderFrame and map.BorderFrame.NineSlice and NineSliceUtil
			and NineSliceUtil.GetLayout(METAL_LAYOUT)) and true or false
	end
	return metal
end

-- Fills `frame` with the rock, tiled by hand as the player does: a texture's own
-- tiling stretches it once the frame grows past one tile. One 256px tile per 256 units.
local function AddRock(frame, insets)
	local rock = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	rock:SetTexture(ROCK, "REPEAT", "REPEAT")
	rock:SetPoint("TOPLEFT", insets.left, -insets.top)
	rock:SetPoint("BOTTOMRIGHT", -insets.right, insets.bottom)
	local function Fit(width, height)
		rock:SetTexCoord(0, (width - insets.left - insets.right) / TILE, 0, (height - insets.top - insets.bottom) / TILE)
	end
	frame:HookScript("OnSizeChanged", function(_, width, height) Fit(width, height) end)
	Fit(frame:GetSize())
end

-- Gives `frame` (a BackdropTemplate frame) its border and background. Returns the
-- height of the title bar the border draws across the top -- 0 for the dialog border --
-- so the caller can keep its content clear of it.
function SpokenZones:SkinFrame(frame)
	if self:UsesMetalFrames() then
		local slice = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
		slice:SetAllPoints()
		NineSliceUtil.ApplyLayoutByName(slice, METAL_LAYOUT)
		frame.NineSlice = slice
		AddRock(frame, METAL_INSETS)
		return METAL_INSETS.top
	end
	frame:SetBackdrop({
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		edgeSize = 32,
		insets = DIALOG_INSETS,
	})
	AddRock(frame, DIALOG_INSETS)
	return 0
end
