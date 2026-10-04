-- The subtitle shows at most Lines at Once lines (3 unless set, 1 to 4): a longer line is split
-- into pages of up to that many, at sentence ends where a sentence fits, at its phrases where it
-- does not, and between words only for a phrase too long on its own. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local Expect, Failures = H.Expecter(stub.print)
local SPOKEN = here .. "/../../addons/Spoken/"
local QUESTS = here .. "/../../addons/Spoken_Quests/"

_G.UISpecialFrames = _G.UISpecialFrames or {}
stub.SetClient("11509"); stub.ResetSound(); stub.ResetTimers(); stub.ResetFrames()
stub.settingsCategories = {}; stub.ldbObjects = {}; stub.dbIcons = {}
stub.world.questID = 0; stub.ShowPanel(nil)
stub.LoadQuests(QUESTS, SPOKEN)
local Subtitle = _G.SpokenEnv.Subtitle
-- The stub measures 7 per character, so a line holds 68 of them (512 less 16 each side).
Subtitle.measure = CreateFrame("Frame"):CreateFontString()

local function Words(text)
    local words = {}
    for word in text:gmatch("%S+") do words[#words + 1] = word end
    return table.concat(words, " ")
end

local short = "A short line."
Expect("a line of four lines or fewer is one page", #Subtitle:Paginate(short), 1)

-- Twelve sentences of about 50 characters: well past four lines.
local sentences = {}
for i = 1, 12 do
    sentences[i] = string.format("Sentence number %02d tells a little more of the story.", i)
end
local long = table.concat(sentences, " ")
local pages = Subtitle:Paginate(long)
local most = 0
for _, page in ipairs(pages) do most = math.max(most, #Subtitle:Wrap(page)) end
Expect("a long line is split into several pages", #pages > 2, true)
Expect("...none longer than four lines", most <= 4, true)
Expect("...each ending at a sentence end", pages[1]:sub(-1), ".")
Expect("...and together they give back every word, in order", Words(table.concat(pages, " ")), Words(long))

-- One sentence longer than a page: cut between words.
local run = {}
for i = 1, 80 do run[i] = "word" .. i end
local endless = table.concat(run, " ") .. "."
pages = Subtitle:Paginate(endless)
most = 0
for _, page in ipairs(pages) do most = math.max(most, #Subtitle:Wrap(page)) end
Expect("a sentence longer than a page is cut between words", #pages > 1 and most <= 4, true)
Expect("...losing none of them", Words(table.concat(pages, " ")), Words(endless))

-- One line at a time: a sentence too long for it breaks at its phrases, never mid-phrase.
local cfg = _G.SpokenEnv.Addon.db.profile.Transcript
cfg.SubtitleLines = 1
local phrased = "When the war ended, the orcs were placed in camps, guarded by the Alliance, and the land was quiet for a time."
pages = Subtitle:Paginate(phrased)
local atPhrases = #pages > 1
for index = 1, #pages - 1 do
    if not pages[index]:find(",$") then atPhrases = false end
end
Expect("one line at a time, a long sentence turns its pages at its commas", atPhrases, true)
Expect("...every page one line", (function()
    for _, page in ipairs(pages) do if #Subtitle:Wrap(page) > 1 then return false end end
    return true end)(), true)
Expect("...losing no words", Words(table.concat(pages, " ")), Words(phrased))
cfg.SubtitleLines = 3

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll subtitle page tests passed")
