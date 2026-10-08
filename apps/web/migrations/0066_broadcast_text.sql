-- What the game's BroadcastText table says in each language: the language-neutral id behind an
-- NPC's gossip text. No client API exposes the id, and Classic clients ship almost none of the
-- table, so it is collected from the server's answers players' clients cache (DBCache.bin).
--
-- One row per id per language: the newest client build's text wins, because a hotfix edits a
-- row's text in place and keeps its id.
--
-- Additive: new tables the previous release never reads.

create table if not exists "broadcast_text" (
  "lang"            text        not null,
  "broadcastTextId" integer     not null,
  -- Text for a male speaker, Text1 for a female one; either may be empty.
  "text"            text        not null,
  "text1"           text        not null,
  -- The client build number that sent this text, e.g. 70245; null when the source has none.
  "build"           integer,
  -- Where the row came from; 'cache' is a player's upload.
  "source"          text        not null,
  -- How many uploads have carried this row, whatever text they had.
  "observations"    integer     not null default 1,
  "updatedAt"       timestamptz not null default now(),
  primary key ("lang", "broadcastTextId")
);

-- Matching a contribution's text to its id looks the text up within one language.
create index if not exists "broadcast_text_lang_text_idx" on "broadcast_text" ("lang", md5("text"));
create index if not exists "broadcast_text_lang_text1_idx" on "broadcast_text" ("lang", md5("text1"));

-- One row per cache upload, for knowing who sent what if a language's rows turn out wrong.
create table if not exists "broadcast_text_upload" (
  "id"        serial      primary key,
  "userId"    text        references "user" ("id") on delete set null,
  "lang"      text        not null,
  "build"     integer,
  "texts"     integer     not null,
  "added"     integer     not null,
  "changed"   integer     not null,
  "createdAt" timestamptz not null default now()
);
