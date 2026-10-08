-- What the game's BroadcastText table says in each language: the language-neutral id behind an
-- NPC's gossip text. No client API exposes the id, and Classic clients ship almost none of the
-- table, so it is collected from the server's answers players' clients cache (DBCache.bin) and
-- from Efficient Games' published copy of the same caches (scripts/import-eg-link.mts).
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
  "source"          text        not null check ("source" in ('cache', 'eglink')),
  -- How many uploads or imports have carried this row, whatever text they had.
  "observations"    integer     not null default 1,
  "updatedAt"       timestamptz not null default now(),
  primary key ("lang", "broadcastTextId")
);

-- Matching a contribution's text to its id looks the text up within one language.
create index if not exists "broadcast_text_lang_text_idx" on "broadcast_text" ("lang", md5("text"));
create index if not exists "broadcast_text_lang_text1_idx" on "broadcast_text" ("lang", md5("text1"));

-- Which NPC or object showed which broadcast text, as Efficient Games' players recorded it.
-- The id is language-neutral, so one row serves every language.
create table if not exists "broadcast_text_speaker" (
  "entityKind"      text    not null check ("entityKind" in ('npc', 'object')),
  "entityId"        integer not null,
  "broadcastTextId" integer not null,
  "window"          text    not null check ("window" in ('gossip', 'greeting')),
  "source"          text    not null check ("source" in ('eglink')),
  primary key ("entityKind", "entityId", "broadcastTextId", "window")
);

create index if not exists "broadcast_text_speaker_id_idx" on "broadcast_text_speaker" ("broadcastTextId");

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
