-- SpokenBooks -- the language axis of the sound packs, as SpokenQuests has it.
--
-- Three identifiers, deliberately distinct:
--
--   client locale     GetLocale(). What the page on screen is written in, and so which index
--                     finds it (see Reader.lua).
--
--   pack language     The `language` a pack's Data/Sounds.lua declares. Absent is English:
--                     every pack published before the field was read is an English pack.
--
--   voice language    What the player chose to hear. "auto" follows the client.
--
-- A page is narrated in the voice language, then the fallback language, then not at all.
-- The page id is the same in every language, so every pack names a page the same way and
-- falling back is per page.

local ADDON_NAME, SpokenBooks = ...

-- Kept in step with SpokenZones.LOCALES (addons/SpokenZones/Language.lua): the addons sit
-- side by side, and a language offered in one and missing from the other is a setting the
-- player makes once and finds half-honoured. tests/lua/books_language_test.lua holds them
-- together.
SpokenBooks.LOCALES = {
	{ code = "enUS", name = "English", native = "English" },
	{ code = "deDE", name = "German", native = "Deutsch" },
	{ code = "esES", name = "Spanish (EU)", native = "Español (España)" },
	{ code = "esMX", name = "Spanish (AL)", native = "Español (América Latina)" },
	{ code = "frFR", name = "French", native = "Français" },
	{ code = "ptBR", name = "Portuguese", native = "Português" },
	{ code = "ruRU", name = "Russian", native = "Русский" },
	{ code = "koKR", name = "Korean", native = "한국어" },
	{ code = "zhCN", name = "Chinese (S)", native = "简体中文" },
	{ code = "zhTW", name = "Chinese (T)", native = "繁體中文" },
}

SpokenBooks.BASE_LANGUAGE = "enUS"
-- "Follow the client": stored as itself rather than resolved, so a player who never chose
-- starts hearing German the day a German pack is installed.
SpokenBooks.AUTO_LANGUAGE = "auto"

local byCode = {}
for _, locale in ipairs(SpokenBooks.LOCALES) do
	byCode[locale.code] = locale
end

--- A code this addon can speak of, or English: absent, empty and unknown all read as enUS.
function SpokenBooks:NormalizeLanguage(code)
	if code and byCode[code] then
		return code
	end
	return self.BASE_LANGUAGE
end

function SpokenBooks:GetLanguageName(code)
	local locale = code and byCode[code]
	if not locale then
		return tostring(code)
	end
	-- The endonym, so every language names itself: a picker lists them all at
	-- once, and translated exonyms would need a table per interface language for
	-- what one field already says.
	return locale.native or locale.name
end

function SpokenBooks:GetClientLanguage()
	return self:NormalizeLanguage(GetLocale and GetLocale())
end

--- The language the player wants to hear, resolved: "auto" becomes the client's.
function SpokenBooks:GetVoiceLanguage()
	local stored = SpokenBooksDB and SpokenBooksDB.voiceLanguage
	if stored == nil or stored == self.AUTO_LANGUAGE or not byCode[stored] then
		return self:GetClientLanguage()
	end
	return stored
end

--- The language to try when the voice language has no clip for a page. Nil means none: the
--- page is silent rather than read in a language nobody asked for.
function SpokenBooks:GetFallbackLanguage()
	local stored = SpokenBooksDB and SpokenBooksDB.fallbackLanguage
	if stored == nil then
		return self.BASE_LANGUAGE
	end
	if stored == "none" or not byCode[stored] then
		return nil
	end
	return stored
end

--- The languages a page may be read in, most wanted first. Never more than two.
function SpokenBooks:LanguageOrder()
	local voice = self:GetVoiceLanguage()
	local order = { voice }
	local fallback = self:GetFallbackLanguage()
	if fallback and fallback ~= voice then
		table.insert(order, fallback)
	end
	return order
end

--- The language a pack is recorded in.
function SpokenBooks:PackLanguage(pack)
	return self:NormalizeLanguage(pack and pack.language)
end

--- The entries a voice picker offers: its own, then every language an installed pack
--- speaks, in LOCALES order, then the language the player has stored if it is not one of
--- those.
---
--- A language with no pack is a setting that cannot be kept -- choosing it reads every page
--- in silence -- so listing it offers a choice whose only result is no sound. The stored
--- value stays listed anyway, because a picker that cannot show what it is set to is a
--- control in an unknown state. The pack list is where a player reads that the pack behind
--- it is gone.
---@param first string The dropdown's own entry -- Auto, or None
---@param stored string|nil What the player has chosen
---@return string[] codes
function SpokenBooks:GetOfferedLanguages(first, stored)
	local installed = {}
	for _, pack in ipairs(self:GetAudioPacks()) do
		installed[self:PackLanguage(pack)] = true
	end
	local offered, seen = { first }, { [first] = true }
	for _, locale in ipairs(self.LOCALES) do
		if installed[locale.code] then
			table.insert(offered, locale.code)
			seen[locale.code] = true
		end
	end
	if stored and not seen[stored] then
		table.insert(offered, stored)
	end
	return offered
end

--- The language the player's packs speak to them: the first in LanguageOrder that an
--- installed pack is recorded in, or the voice language when none is. What a report is filed
--- under when there is no clip to ask, and what a contribution says the player was hearing.
function SpokenBooks:GetPackLanguage()
	local order = self:LanguageOrder()
	local packs = self:GetAudioPacks()
	for _, language in ipairs(order) do
		for _, pack in ipairs(packs) do
			if self:PackLanguage(pack) == language then
				return language
			end
		end
	end
	return order[1]
end
