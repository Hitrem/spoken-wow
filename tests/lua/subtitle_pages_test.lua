-- The subtitle shows Sentences at Once whole sentences (3 unless set, 1 to 4) and never more than
-- four lines: a longer line is split into pages of whole sentences, a sentence longer than four
-- lines at its phrases, and between words only for a phrase too long on its own. Run with
-- `make test-player`.
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

-- The most any page of `list` has of what `measure` counts.
local function Most(list, measure)
    local top = 0
    for _, page in ipairs(list) do top = math.max(top, measure(page)) end
    return top
end
local function Lines(page) return #Subtitle:Wrap(page) end

-- Twelve sentences of about 50 characters: well past four lines.
local sentences = {}
for i = 1, 12 do
    sentences[i] = string.format("Sentence number %02d tells a little more of the story.", i)
end
local long = table.concat(sentences, " ")
local pages = Subtitle:Paginate(long)
local most = Most(pages, Lines)
Expect("a long line is split into several pages", #pages > 2, true)
Expect("...none longer than four lines", most <= 4, true)
Expect("...each ending at a sentence end", pages[1]:sub(-1), ".")
Expect("...and together they give back every word, in order", Words(table.concat(pages, " ")), Words(long))

-- One phrase longer than four lines: cut between words.
local run = {}
for i = 1, 80 do run[i] = "word" .. i end
local endless = table.concat(run, " ") .. "."
pages = Subtitle:Paginate(endless)
most = Most(pages, Lines)
Expect("a phrase longer than four lines is cut between words", #pages > 1 and most <= 4, true)
Expect("...losing none of them", Words(table.concat(pages, " ")), Words(endless))

local cfg = _G.SpokenEnv.Addon.db.profile.Transcript
local function Count(page)
    local n = 0
    for _ in page:gmatch("[.!?]") do n = n + 1 end
    return n
end
Expect("three sentences to a page unless set", Most(Subtitle:Paginate(long), Count), 3)

-- One sentence at a time: each page one whole sentence, two lines if it needs them.
cfg.SubtitleSentences = 1
local mixed = "The war ended. When the war ended, the orcs who had survived the long march north were placed in the camps. The land was quiet."
pages = Subtitle:Paginate(mixed)
Expect("one at a time, a page for each sentence", #pages, 3)
Expect("...the long one whole, on the lines it needs", #Subtitle:Wrap(pages[2]), 2)
Expect("...losing no words", Words(table.concat(pages, " ")), Words(mixed))

-- A sentence longer than four lines turns at its phrases, never mid-phrase.
local phrases = {}
for i = 1, 12 do phrases[i] = string.format("and then phrase number %02d went by", i) end
local rambling = table.concat(phrases, ", ") .. "."
pages = Subtitle:Paginate(rambling)
local atPhrases = #pages > 1
for index = 1, #pages - 1 do
    if not pages[index]:find(",$") then atPhrases = false end
end
Expect("a sentence past four lines turns its pages at its commas", atPhrases, true)
Expect("...none longer than four lines", Most(pages, function(page) return #Subtitle:Wrap(page) end) <= 4, true)
Expect("...losing no words", Words(table.concat(pages, " ")), Words(rambling))
cfg.SubtitleSentences = 3

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll subtitle page tests passed")
