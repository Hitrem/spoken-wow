-- The lines an NPC says in chat after a quest: armed by this player's own accept or turn-in,
-- matched exactly, played once. Run with `make test-player`.
--
-- The failure this guards against is the busy zone: the NPC's line reaches everybody standing
-- near it, so a matcher that listened without being armed, or matched loosely, would read
-- every other player's turn-in aloud.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local world = stub.world
local QUESTS = here .. "/../../addons/SpokenQuests/"
local SPOKEN = here .. "/../../addons/SpokenPlayer/"
local Expect, Failures = H.Expecter(print)

local SPEAKER = 500
local SPEAKER_GUID = "Creature-0-0-0-0-500-0"
local GOSSIP_HASH = "0123456789abcdef0123456789abcdef"

-- The shape FollowupLines.lua is generated in; a fixture rather than the real export, so a
-- regenerated export cannot change what these scenarios mean.
local FIXTURE = {
    ["end"] = {
        [300] = {
            { id = 1, speaker = SPEAKER, delay = 2, chat = "say", male = "Thanks, $n!", female = "Thanks, $n!" },
            { id = 2, speaker = SPEAKER, delay = 6, chat = "say",
                male = "Well done.  $GHe : She; is a fine $r $c.", female = "Well done.  $GHe : She; is a fine $r $c." },
        },
        -- A script step picking one of several texts at random: siblings at one delay.
        [302] = {
            { id = 10, speaker = SPEAKER, delay = 2, chat = "say", male = "Onward!", female = "Onward!" },
            { id = 11, speaker = SPEAKER, delay = 2, chat = "say", male = "Forward!", female = "Forward!" },
            { id = 12, speaker = SPEAKER, delay = 5, chat = "yell", male = "Victory!", female = "Victory!" },
        },
        -- A speaker with no gossip of its own, for the placeholder's second choice.
        [303] = {
            { id = 20, speaker = 777, delay = 0, chat = "say", male = "Done.", female = "Done." },
        },
    },
    ["start"] = {
        [301] = {
            { id = 30, speaker = SPEAKER, delay = 1, chat = "say", male = "Go, $n.", female = "Go, $n." },
        },
    },
}

local lookup = { [GOSSIP_HASH] = 2 }
for _, q in ipairs({ 300, 301, 302, 303 }) do
    lookup[q .. "-accept"] = 2; lookup[q .. "-complete"] = 2
end

local queued = {}
local function Boot(client)
    stub.SetClient(client or "11509"); stub.ResetSound(); stub.ResetTimers()
    stub.ldbObjects = {}; stub.dbIcons = {}
    world.questID = 0; stub.ShowPanel(nil); world.gossipText = nil; world.greetingText = nil
    world.playerName = "Tester"; world.unitSex = 2
    world.playerRace = "Dwarf"; world.playerClass = "Paladin"
    stub.SetLocale("enUS")
    local VO, env = stub.LoadQuests(QUESTS, SPOKEN)
    VO.FollowupLines = FIXTURE
    dofile(QUESTS .. "Followup.lua")
    VO.Addon:OnInitialize()
    VO.DataModules:Register("TestPack", {
        SoundLengthLookupByFileName = lookup,
        GetSoundPath = function(_, fileName) return fileName .. ".ogg" end,
        GossipLookupByNPCID = { [SPEAKER] = { ["Hail."] = GOSSIP_HASH } },
    })
    stub.Advance(2)   -- the deferred pack load
    _G.Spoken:RegisterCallback("CLIP_QUEUED", function(clip)
        if clip.source == VO.Player.source then table.insert(queued, clip) end
    end)
    return VO, _G.Spoken
end

local VO, Spoken = Boot()

local function Reset()
    for i = #queued, 1, -1 do queued[i] = nil end
    Spoken:StopAll()
    VO.Followup.armed = {}
    stub.SetLocale("enUS")
    stub.Advance(1)
end

local function Say(text, guid, sender, event)
    stub.FireEvent(event or "CHAT_MSG_MONSTER_SAY", text, sender or "Marshal Test", "", "", "", "", 0, 0, "", 0, 1,
        guid)
end

local function Keys()
    local keys = {}
    for _, clip in ipairs(queued) do table.insert(keys, clip.key) end
    return table.concat(keys, ", ")
end

---------------------------------------------------------------- unarmed
Reset()
Say("Thanks, Tester!", SPEAKER_GUID)
Expect("a line nobody armed is ignored", Keys(), "")
Expect("...and arms nothing", #VO.Followup.armed, 0)

---------------------------------------------------------------- arm, match, consume
Reset()
stub.FireEvent("QUEST_TURNED_IN", 300, 0, 0)
Expect("the player's own turn-in arms the quest's lines", #VO.Followup.armed, 2)
stub.Advance(2)
Say("Thanks, Tester!", SPEAKER_GUID)
Expect("the matching line plays", Keys(), "followup:1")
local clip = queued[1]
Expect("...as a follow-up, not a quest or gossip line", clip and clip.event, VO.Enums.SoundEvent.QuestFollowup)
Expect("...at normal priority, so the turn-in's own gossip rule does not drop it", clip and clip.priority, "normal")
Expect("...headed by the NPC who said it", clip and clip.present.header, "Marshal Test")
Expect("...carrying what was said", clip and clip.text, "Thanks, Tester!")
Expect("...on the speaker's gossip clip, standing in for the recording",
    clip and clip.path:match("[^\\]+$"), GOSSIP_HASH .. ".ogg")
Expect("...and is consumed", #VO.Followup.armed, 1)
Say("Thanks, Tester!", SPEAKER_GUID)
Expect("the same line said again does not replay", Keys(), "followup:1")

-- Double spaces collapsed, gender and race/class tokens filled for this player.
Say("Well done. He is a fine Dwarf Paladin.", SPEAKER_GUID)
Expect("tokens and whitespace are normalised before comparing", Keys(), "followup:1, followup:2")
Expect("...and nothing is left armed", #VO.Followup.armed, 0)

---------------------------------------------------------------- another player's turn-in
Reset()
stub.FireEvent("QUEST_TURNED_IN", 300, 0, 0)
Say("Thanks, Someone!", SPEAKER_GUID)
Expect("a line naming another player does not match", Keys(), "")
Expect("...and does not use up ours", #VO.Followup.armed, 2)

---------------------------------------------------------------- the wrong speaker
Say("Thanks, Tester!", "Creature-0-0-0-0-999-0")
Expect("the right words from a different NPC do not match", Keys(), "")
Say("Thanks, Tester!", nil)
Expect("...but a client with no GUID falls back on the text", Keys(), "followup:1")

---------------------------------------------------------------- expiry
Reset()
stub.FireEvent("QUEST_TURNED_IN", 300, 0, 0)
stub.Advance(6 + 10 + 1)   -- the last line's delay, the slack, and a second more
Say("Thanks, Tester!", SPEAKER_GUID)
Expect("an armed line expires after its script could have run", Keys(), "")
Expect("...and is dropped", #VO.Followup.armed, 0)

---------------------------------------------------------------- accept
Reset()
stub.FireEvent("QUEST_ACCEPTED", 4, 301)
Say("Go, Tester.", SPEAKER_GUID)
Expect("accepting a quest arms its start lines (Classic's index, questID)", Keys(), "followup:30")
Reset()
stub.FireEvent("QUEST_ACCEPTED", 301)
Say("Go, Tester.", SPEAKER_GUID)
Expect("...and mainline's questID alone", Keys(), "followup:30")

---------------------------------------------------------------- random-text siblings
Reset()
stub.FireEvent("QUEST_TURNED_IN", 302, 0, 0)
Say("Forward!", SPEAKER_GUID)
Expect("one of a step's random texts plays", Keys(), "followup:11")
Expect("...and its siblings at that step are consumed with it", #VO.Followup.armed, 1)
Expect("...leaving the next step", VO.Followup.armed[1] and VO.Followup.armed[1].line.id, 12)

Reset()
stub.SetLocale("deDE")
stub.FireEvent("QUEST_TURNED_IN", 302, 0, 0)
Say("Vorwärts!", SPEAKER_GUID)
Expect("a translated client matches by speaker, earliest step first", Keys(), "followup:10")
Say("Sieg!", SPEAKER_GUID, nil, "CHAT_MSG_MONSTER_YELL")
Expect("...and the next line is the next step, not the other random text", Keys(), "followup:10, followup:12")
Say("Sieg!", SPEAKER_GUID)
Expect("...with nothing after the last one", Keys(), "followup:10, followup:12")

Reset()
stub.SetLocale("deDE")
stub.FireEvent("QUEST_TURNED_IN", 302, 0, 0)
Say("Vorwärts!", nil)
Expect("a translated client with no speaker to go on plays nothing", Keys(), "")
Say("Vorwärts!", "Creature-0-0-0-0-999-0")
Expect("...nor from a different NPC", Keys(), "")

---------------------------------------------------------------- queueing
Reset()
world.questID = 303; world.title = "Test Quest"; world.rewardText = "Done."
stub.ShowPanel("QuestFrameRewardPanel")
VO.Addon:QUEST_COMPLETE()
world.questID = 0; stub.ShowPanel(nil)
stub.FireEvent("QUEST_TURNED_IN", 303, 0, 0)
Say("Done.", "Creature-0-0-0-0-777-0")
Expect("a follow-up queues behind the turn-in's voiceover", Keys(), "303-complete, followup:20")
Expect("...with the quest's own clip standing in where the speaker has no gossip",
    queued[2] and queued[2].path:match("[^\\]+$"), "303-complete.ogg")

---------------------------------------------------------------- /spq followup
-- The in-game test: arms the quest and replays its chat through the real matcher, one
-- line per random-text group, on the script's own delays.
Reset()
VO.FollowupSoundLengths = { [10] = 1.5 }
VO.Followup:Simulate("302")
Expect("/spq followup arms the quest", #VO.Followup.armed, 3)
stub.Advance(6)
Expect("...and plays one line per delay, not every random alternative", Keys(), "followup:10, followup:12")
Expect("...on the line's own recording where there is one",
    queued[1] and queued[1].path, [[Interface\AddOns\SpokenQuests\Sounds\followup\10.mp3]])
Expect("...and the placeholder where there is not", queued[2] and queued[2].path:match("[^\\]+$"),
    GOSSIP_HASH .. ".ogg")
VO.FollowupSoundLengths = nil

---------------------------------------------------------------- switched off
Reset()
VO.Addon.db.profile.Audio.FollowupLines = false
stub.FireEvent("QUEST_TURNED_IN", 300, 0, 0)
Expect("the option off arms nothing", #VO.Followup.armed, 0)
VO.Addon.db.profile.Audio.FollowupLines = true
VO.Addon:SetAutoplay(false)
stub.FireEvent("QUEST_TURNED_IN", 300, 0, 0)
Expect("...nor does autoplay off", #VO.Followup.armed, 0)
VO.Addon:SetAutoplay(true)

---------------------------------------------------------------- a private-server client
-- No QUEST_TURNED_IN there: the turn-in is the GetQuestReward call, made while the reward
-- dialog still says which quest it is.
_G.GetQuestReward = function() end
_G.AcceptQuest = function() end
for i = #queued, 1, -1 do queued[i] = nil end
VO, Spoken = Boot("3.3.5")
world.questID = 300; world.title = "Test Quest"; world.rewardText = "Done."
_G.GetQuestReward(1)
world.questID = 0
Expect("3.3.5: GetQuestReward arms the turn-in", #VO.Followup.armed, 2)
stub.FireEvent("QUEST_TURNED_IN", 302, 0, 0)
Expect("...and QUEST_TURNED_IN, which it has no such event for, is not listened to", #VO.Followup.armed, 2)
Say("Thanks, Tester!", nil)
Expect("...and the line matches on its text", Keys(), "followup:1")
world.questID = 301; world.questText = "Go."
_G.AcceptQuest()
world.questID = 0
Expect("3.3.5: AcceptQuest arms the start lines", #VO.Followup.armed, 2)

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll quest follow-up tests passed")
