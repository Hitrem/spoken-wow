-- SpokenZones -- the play/pause button shown next to a lore description.
--
-- A factory in the same shape as SpokenZones:CreateTextView: anchor the returned
-- button yourself, then call SetTarget whenever the panel's content changes.
--
-- The player's own round button (Spoken:CreateRoundButton), the one its subtitle shows, so the
-- two are one button: Play to start the story, Stop while it is read, Replay once stopped, and
-- Play again when it has ended. Report sits beside it (SpokenZones:CreateReportIcon).

local ADDON_NAME, SpokenZones = ...

local L = SpokenZones.L

local ROUND_SIZE = 24
-- Our own copies, not paths into Spoken: OwnRound only draws when the player is missing,
-- and a missing texture draws as solid green.
local RING = [[Interface\AddOns\Spoken_Zones\Textures\SettingsButton]]
local PORTRAIT_ATLAS = [[Interface\AddOns\Spoken_Zones\Textures\PortraitFrameAtlas]]
local PORTRAIT_ATLAS_SIZE = 512
local BUG = [[Interface\HelpFrame\HelpIcon-Bug]]

local AudioButton = {}

--------------------------------------------------------------------------------
-- The round button
--------------------------------------------------------------------------------

-- The same button drawn here, for a client without the player: there is nothing to play then,
-- but Report still has a story to report on.
local function OwnRound(parent, kind, icon)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(ROUND_SIZE, ROUND_SIZE)
	local ring = button:CreateTexture(nil, "BACKGROUND")
	ring:SetTexture(RING)
	ring:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
	ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -3)
	local glyph = button:CreateTexture(nil, "ARTWORK")
	glyph:SetAlpha(0.85)
	button.ring, button.glyph = ring, glyph
	button:HookScript("OnEnter", function() glyph:SetAlpha(1) end)
	button:HookScript("OnLeave", function() glyph:SetAlpha(0.85) end)
	if kind == "play" then
		glyph:SetPoint("CENTER")
		glyph:SetSize(12, 12)
		glyph:SetTexture(PORTRAIT_ATLAS)
		-- Without the player nothing plays, so only Play is ever shown here.
		function button:SetState(state)
			glyph:SetTexCoord(0, 93 / PORTRAIT_ATLAS_SIZE, 419 / PORTRAIT_ATLAS_SIZE, 512 / PORTRAIT_ATLAS_SIZE)
			self.state, self.playing = state, state == "stop"
		end
		function button:SetPlaying(playing) self:SetState(playing and "stop" or "play") end
		button:SetState("play")
	else
		if kind == "icon" and icon then
			-- Filling the ring's dark middle, cut round, as the player's own is (Actions.RoundPicture).
			glyph:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
			glyph:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
			glyph:SetTexture(icon)
			glyph:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			local mask = button.CreateMaskTexture and glyph.AddMaskTexture and button:CreateMaskTexture()
			if type(mask) == "table" then
				mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				mask:SetAllPoints(glyph)
				glyph:AddMaskTexture(mask)
			elseif SetPortraitToTexture then
				SetPortraitToTexture(glyph, icon)
			end
			-- No vignette over it, as the player's has: that art is the player's, absent here.
		else
			glyph:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4)
			glyph:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)
			glyph:SetTexture(BUG)
		end
	end
	return button
end

--- The player's round button: `kind` "play", "report", or "icon" with the texture `icon`.
function SpokenZones:CreateRoundButton(parent, kind, icon)
	local Spoken = _G.Spoken
	if Spoken and Spoken.CreateRoundButton then
		return Spoken:CreateRoundButton(parent, kind, nil, icon)
	end
	return OwnRound(parent, kind, icon)
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- nil areaKey means the zone itself. Passing a nil mapID parks the button: it
-- has nothing to play, so it hides.
function AudioButton:SetTarget(mapID, areaKey)
	self.mapID = mapID
	self.areaKey = areaKey
	self:Refresh()
end

function AudioButton:Refresh()
	if not SpokenZones:IsVoiceEnabled() or not self.mapID then
		self:Hide()
		return
	end

	if not SpokenZones:HasAudio(self.mapID, self.areaKey) then
		self:Hide()
		return
	end

	self:Show()
	-- Stop while this story is read, Replay while it is stopped at the head, Play otherwise.
	local state = "play"
	if SpokenZones:IsLoreAtHead(self.mapID, self.areaKey) and SpokenZones:IsPaused() then
		state = "replay"
	elseif SpokenZones:IsPlayingLore(self.mapID, self.areaKey) then
		state = "stop"
	end
	self:SetState(state)
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function SpokenZones:CreateAudioButton(parent)
	local button = SpokenZones:CreateRoundButton(parent, "play")
	button:Hide()

	button.SetTarget = AudioButton.SetTarget
	button.Refresh = AudioButton.Refresh

	-- This story speaking, or at the head of the queue and paused: pause or resume it, as the
	-- subtitle's button does. Anything else, including this story at the head unstarted because
	-- a gate holds it (combat, a cinematic): start it. Toggling then would pause the whole queue.
	button:SetScript("OnClick", function(self)
		if not self.mapID then
			return
		end
		if SpokenZones:IsPlayingLore(self.mapID, self.areaKey)
			or (SpokenZones:IsLoreAtHead(self.mapID, self.areaKey) and SpokenZones:IsPaused()) then
			SpokenLayout.Sound("U_CHAT_SCROLL_BUTTON")
			_G.Spoken:TogglePause()
		else
			SpokenZones:PlayLore(self.mapID, self.areaKey)
		end
	end)

	button:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		if self.state == "stop" then
			GameTooltip:SetText(L.STOP)
			GameTooltip:AddLine(L.STOP_TOOLTIP, 1, 0.8, 0.2, true)
		elseif self.state == "replay" then
			GameTooltip:SetText(L.REPLAY)
			GameTooltip:AddLine(L.REPLAY_TOOLTIP, 1, 0.8, 0.2, true)
		else
			GameTooltip:SetText(L.PLAY)
			GameTooltip:AddLine(L.AUDIO_READ_TIP, 1, 0.8, 0.2, true)
		end
		GameTooltip:Show()
	end)

	button:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Both panels can show the same entry at once, and either can start playback,
	-- so every button re-reads the shared state rather than tracking its own.
	SpokenZones:OnAudioChanged(function()
		button:Refresh()
	end)

	return button
end
