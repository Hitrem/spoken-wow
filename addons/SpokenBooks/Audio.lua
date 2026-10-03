-- What a page sounds like: which pack narrates it, where the file is, how long it runs.
--
-- Narration ships in a separate sound-pack addon because it is a large download, and it is
-- optional: without one there is nothing to play, so the addon stays quiet and says why.
--
-- THERE IS NO STAND-IN CLIP, for the reason addons/SpokenZones/Audio.lua gives at length:
-- substituting unrelated audio is worse than silence, because silence is honest about what
-- is missing and a borrowed clip is not.

local ADDON_NAME, SpokenBooks = ...

local L = SpokenBooks.L

-- The pack table shape this version knows how to read. A pack declaring anything else is
-- ignored with a warning: refusing to read it is recoverable, guessing at an unknown layout
-- plays silence and reports nothing.
local PACK_FORMAT = 1

-- The player's own book art. Pointed at rather than copied: SpokenPlayer is installed
-- alongside this addon by definition -- it is what the clips are queued through -- and a
-- second copy of the same texture is a second thing to keep in step.
local BOOK_TEXTURE = [[Interface\AddOns\SpokenPlayer\Textures\Book]]

--- What one registry holds in a format this version can read, by folder name. The packs and
--- the overlays register the same entry shape into two tables (see GetAudioOverlays).
local function readRegistry(registry)
	local packs = {}
	for name, pack in pairs(registry or {}) do
		if type(pack) == "table" and pack.version == PACK_FORMAT and type(pack.pages) == "table" then
			pack.addon = pack.addon or name
			table.insert(packs, pack)
		end
	end
	table.sort(packs, function(a, b) return (a.addon or "") < (b.addon or "") end)
	return packs
end

--- Every installed pack this version can read, newest format first.
function SpokenBooks:GetAudioPacks()
	return readRegistry(_G.SpokenBooksAudioPacks)
end

--- Every installed voice-acted overlay this version can read, by folder name.
---
--- An overlay holds a voice actor's recordings for some pages and nothing else -- the same
--- entry shape as a pack, covering a handful of pages. It registers into a table of its own
--- rather than SpokenBooksAudioPacks because every earlier release treats anything in that
--- table as a whole pack: it would count an overlay as "a pack installed", stop telling a
--- player with nothing else that they need one, and then read almost nothing. A table those
--- releases never read cannot mislead them.
---
--- One in a format this build cannot read is skipped quietly: the pages it would have
--- covered still play from the pack underneath, so nothing goes silent for it.
function SpokenBooks:GetAudioOverlays()
	return readRegistry(_G.SpokenBooksAudioOverlays)
end

--- Everything that can voice a page, overlays before packs: within a language a human
--- reading is what installing an overlay asked for.
function SpokenBooks:GetAudioSources()
	local sources = self:GetAudioOverlays()
	for _, pack in ipairs(self:GetAudioPacks()) do
		table.insert(sources, pack)
	end
	return sources
end

-- The buttons the player shows under a book clip: Report, and nothing else. There is no Read
-- button here, unlike the zones strip -- the page is already open on screen, and a button
-- that re-read what the reader is looking at would answer a question nobody asked.
--
-- One table, shared by every clip. The player tells the button which clip it now stands
-- beside; the action holds no state of its own.
local ACTIONS = {
	{
		id = "report",
		-- An icon in the corner rather than a word beside the line, as the zones action is.
		-- The bug icon postdates the three legacy clients, where the texture is
		-- simply missing and the button would be a blank square; `text` is what those draw
		-- instead.
		icon = [[Interface\HelpFrame\HelpIcon-Bug]],
		label = "Report a problem",
		text = "R",
		anchor = "topright",
		tooltip = function(tooltip)
			tooltip:SetText("Report a problem")
			tooltip:AddLine("A bad reading, a mispronounced name, narration that does not "
				.. "match the page -- this gives you a link to say so.", 1, 0.8, 0.2, true)
		end,
		onClick = function(clip)
			if not clip then
				return
			end
			local url = SpokenBooks:ReportURL(clip.pageId, clip.language)
			if url and SpokenBooks.ShowCopyLink then
				SpokenBooks:ShowCopyLink(url,
					"Copy this address and open it in your browser to report a problem with "
						.. "this page.")
			end
		end,
	},
}

--- The clip for a page, as the player's queue wants it, or nil when no pack carries it.
---
--- Language before pack order: a pack in the voice language answers before any other, and a
--- page it lacks falls back to the fallback language's packs -- page by page, so a partial
--- translation still reads what it has.
---
--- Within a language, voice-acted overlays come before the packs: a human reading is what
--- installing one asked for. Only within it, though -- an English recording does not
--- outrank the German pack's reading of the same page for a player who chose German.
function SpokenBooks:ClipFor(pageId)
	local place = self:Data() and self:Data().pages[pageId]
	if not place then
		return nil
	end

	local packs = self:GetAudioSources()
	for _, language in ipairs(self:LanguageOrder()) do
		for _, pack in ipairs(packs) do
			local entry = self:PackLanguage(pack) == language and pack.pages[pageId]
			if entry then
				local book = self:Data().books[place.book]
				local text = entry.text
				if not text and language == self.BASE_LANGUAGE then text = place.text end
				if not text and self.pageText and self.pageText[language] then
					text = self.pageText[language][pageId]
				end
				return {
					key = "b:" .. pageId,
					path = [[Interface\AddOns\]] .. pack.addon .. [[\Sounds\]] .. entry.file .. ".mp3",
					-- 0 means the pack recorded no duration -- an imported take rather than one
					-- this project cut. The player falls back to its own timer; a wrong number
					-- here would reset the Play button mid-sentence.
					length = (entry.len and entry.len > 0) and entry.len or nil,
					pageId = pageId,
					-- What the report is filed under: a fallback page is an English take even
					-- under a German selection, and its report is about that.
					language = language,
					present = {
						header = book and book.title or "",
						transcript = text,
						-- Only where there is more than one page: "page 1 of 1" is noise on a
						-- letter, which is most of this corpus.
						label = (book and #book.pages > 1)
							and format(L.OPT_PAGE_COUNT_FMT, place.number, #book.pages)
							or nil,
						bullet = "book",
						portrait = { kind = "texture", texture = BOOK_TEXTURE },
						actions = ACTIONS,
					},
				}
			end
		end
	end

	return nil
end

--- Why there is no clip, phrased for the player. Distinguishes "you have no sound pack"
--- from "your pack does not cover this page": the first is a download and the second is
--- nothing they can do, and telling them apart is the point of saying anything at all.
function SpokenBooks:DescribeMissingAudio()
	if #self:GetAudioPacks() == 0 then
		return L.OPT_NO_PACK_INSTALLED
	end
	return L.OPT_NO_PACK_AUDIO
end

function SpokenBooks:HasAudio(pageId)
	return self:ClipFor(pageId) ~= nil
end
