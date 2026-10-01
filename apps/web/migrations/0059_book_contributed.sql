-- A page's translation, sent by a player and accepted on the site.
--
-- Until now accepting a books contribution only flipped its status: nothing wrote the text
-- anywhere the explorer reads, so 478 accepted Portuguese pages showed up nowhere.
-- Accepting one now writes the page's row in that language, with origin 'contributed' --
-- quest_line's word for the same thing (0034).
--
-- THE CONTRIBUTION DOES NOT NAME ITS PAGE. The addon sends a page only when its lookup
-- failed, so it has no pageTextID to give: its `page` field, and the contribution's key, is
-- the checksum of the text on screen (naming.mjs's pageChecksum, Contribute.lua). In another
-- language that is the checksum of the translation, which no English index holds. Which
-- English page a translation is of is therefore an answer somebody has to give, and
-- book_page_match is where it is kept: by the contribution's language and key, so every
-- contribution of the same text -- and a contribution sent again later -- finds it.
--
-- One key may match more than one page: a text can stand on two pages, and its checksum
-- with it. Accept writes every page its key matches.
--
-- Additive, per deploy/web/bin/migrate.sh: the check only widens, and the previous release
-- never reads the new table.

alter table "book_line" drop constraint "book_line_origin_check";
alter table "book_line" add constraint "book_line_origin_check"
  check ("origin" in ('extracted', 'edited', 'contributed'));

create table "book_page_match" (
  "lang"      text        not null,
  -- The contribution's key: the checksum of the page as that language's client shows it.
  "key"       text        not null,
  "pageId"    integer     not null,
  "note"      text,
  "createdAt" timestamptz not null default now(),
  primary key ("lang", "key", "pageId")
);
