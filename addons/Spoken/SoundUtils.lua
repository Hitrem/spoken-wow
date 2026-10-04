setfenv(1, SpokenEnv)

-- The bottom of the playback stack: whether sound can be heard, and starting and stopping
-- one file. Everything above this deals in clips; only this file calls PlaySoundFile.
--
-- Merged from the two addons' copies. The audibility predicate is VoiceOverRedux's -- it
-- checks the volumes as well as the toggles, and Master deliberately bypasses the
-- per-channel toggles, which the inherited player got wrong -- and the reasons it returns
-- are ZoneLore's, phrased for the player who is reading them. Compat.lua replaces the
-- four playback functions wholesale on 1.12, 2.4.3 and 3.3.5.
SoundUtils = {}

-- A channel this player switched off on a source's behalf: the quests addon mutes
-- Dialog while its line speaks so the NPC's bark does not talk over it. The queue
-- treats such a channel as audible at admission and lifts the mute before playing on
-- it -- the alternative is refusing every zones clip that arrives during a quest line.
local CHANNEL_CVARS = { SFX = "Sound_EnableSFX", Music = "Sound_EnableMusic", Ambience = "Sound_EnableAmbience", Dialog = "Sound_EnableDialog" }
local mutedByPlayer = {}

-- Muting the game's NPC voices with `fadeOut` fades them first rather than cutting them mid-word:
-- the Dialog volume is stepped down over DIALOG_FADE, the channel switched off, and its volume put
-- back as it was, so the player's own setting is never changed. Unmuted before the fade ends, or
-- at logout, the volume goes straight back.
local DIALOG_FADE, FADE_STEP = 0.5, 0.05
local fade
local function EndFade()
    if not fade then return end
    Addon:CancelTimer(fade.timer)
    if fade.volume then SetCVar("Sound_DialogVolume", fade.volume) end
    fade = nil
end
-- Whether Lower Other Sounds turns NPC voices down while a line speaks (OtherSounds). It fades the
-- Dialog volume itself, so the fade here leaves the volume to it and only switches the channel off
-- at the end: two fades on one volume undid each other.
local function OthersLowerDialog()
    local audio = Addon.db and Addon.db.profile.Audio
    local lower = audio and audio.LowerOthers
    return lower and lower.Enabled and (lower.Dialog or 1) < 1 and OtherSounds and OtherSounds:IsAvailable() or false
end

---@param channel string
---@param muted boolean
---@param fadeOut boolean? fade the Dialog channel out rather than cut it
function SoundUtils:MuteChannel(channel, muted, fadeOut)
    local cvar = CHANNEL_CVARS[channel]
    if not cvar or (mutedByPlayer[channel] or false) == (muted or false) then
        return
    end
    mutedByPlayer[channel] = muted or nil
    if channel == "Dialog" then EndFade() end
    if muted and fadeOut and channel == "Dialog" and Addon and Addon.ScheduleRepeatingTimer then
        local volume = tonumber(GetCVar("Sound_DialogVolume")) or 1
        local ours = not OthersLowerDialog()
        local started = GetTime()
        fade = { volume = ours and volume or nil }
        fade.timer = Addon:ScheduleRepeatingTimer(function()
            local k = (GetTime() - started) / DIALOG_FADE
            if k >= 1 then
                SetCVar(cvar, 0)
                EndFade()
            elseif ours then
                SetCVar("Sound_DialogVolume", volume * (1 - k))
            end
        end, FADE_STEP)
        return
    end
    SetCVar(cvar, muted and 0 or 1)
end

function SoundUtils:IsMutedByPlayer(channel)
    return mutedByPlayer[channel] or false
end

-- The CVar is saved with the client's settings and the record of muting it is not: a
-- logout or /reload mid-line left Dialog off in every later session, with nothing in
-- the new one knowing to lift it. PLAYER_LOGOUT fires on /reload too.
local restoreFrame = CreateFrame("Frame")
restoreFrame:RegisterEvent("PLAYER_LOGOUT")
restoreFrame:SetScript("OnEvent", function()
    for channel in pairs(mutedByPlayer) do
        SoundUtils:MuteChannel(channel, false)
    end
end)

--- Why sound on the given channel cannot be heard right now, or nil when it can.
--- PlaySoundFile returns false both for a missing file and for a muted channel, so
--- without asking first those two are indistinguishable -- and they want opposite
--- responses from whoever is reading the message.
---@param channel string "Master" | "SFX" | "Music" | "Ambience" | "Dialog"
---@return string|nil reason
function SoundUtils:WhyInaudible(channel)
    if tonumber(GetCVar("Sound_EnableAllSound")) ~= 1 then
        return "all sound is disabled"
    end
    if (tonumber(GetCVar("Sound_MasterVolume")) or 1) <= 0 then
        return "the master volume is 0"
    end
    if channel == "Master" then
        return nil
    end
    if tonumber(GetCVar(format("Sound_Enable%s", channel))) ~= 1 then
        return format("the %s sound channel is disabled", channel)
    end
    if (tonumber(GetCVar(format("Sound_%sVolume", channel))) or 1) <= 0 then
        return format("the %s sound channel volume is 0", channel)
    end
    return nil
end

function SoundUtils:IsSoundEnabled(channel)
    return self:WhyInaudible(channel) == nil
end

--- Plays the file and stops it at once, to learn whether it exists. Also false when the
--- channel is muted; ask WhyInaudible first to tell the two apart. The probe has to go
--- out on the channel the clip will play on: without one the client uses SFX, and a
--- player with effects switched off gets every file reported missing.
---@param clip { path: string }
---@param channel string
---@return boolean exists
function SoundUtils:TestSound(clip, channel)
    local willPlay, handle = PlaySoundFile(clip.path, channel)
    if willPlay then
        StopSound(handle)
    end
    return willPlay
end

--- Starts the clip on the channel and records the handle on it, which is the only way to
--- stop it again. Returns whether the client accepted the file.
---@param clip { path: string, handle: number? }
---@param channel string
---@return boolean willPlay
---@return number|nil handle
function SoundUtils:PlaySound(clip, channel)
    local willPlay, handle = PlaySoundFile(clip.path, channel)
    clip.handle = handle
    return willPlay, handle
end

---@param clip { handle: number? }
--- `fadeMs`, where given, fades the voice out over that many milliseconds rather than cutting
--- it: the client's StopSound takes one. The legacy clients stop their own way (Compat.lua),
--- which takes no fade.
function SoundUtils:StopSound(clip, fadeMs)
    if clip.handle then
        if fadeMs then StopSound(clip.handle, fadeMs) else StopSound(clip.handle) end
    end
    clip.handle = nil
end
