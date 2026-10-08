-- Who sent each copy of a contribution, where they said.
--
-- "contribution" keeps the first sender's identity and only counts the rest: the upsert on
-- "dedup" bumps "count" and drops the second player's name on the floor. Triage wants to see
-- who stands behind a line, so each copy sent by a signed-in player or one who typed a name is
-- a row here. A copy sent by neither has no row, which is what makes "count" minus these rows
-- the anonymous senders.
--
-- Backfilled with each row's first sender, the one identity the table kept. Later copies of
-- rows filed before this stay anonymous: there is nothing left to say who sent them.
--
-- Additive: a new table the previous release never reads.

create table if not exists "contribution_sender" (
  "id"             serial primary key,
  "contributionId" integer not null references "contribution" ("id") on delete cascade,
  "userId"         text references "user" ("id") on delete set null,
  "name"           text,
  "createdAt"      timestamptz not null default now()
);

create index if not exists "contribution_sender_contribution_idx"
  on "contribution_sender" ("contributionId");

insert into "contribution_sender" ("contributionId", "userId", "name", "createdAt")
select c."id", c."userId", c."name", c."createdAt"
  from "contribution" c
 where (c."userId" is not null or c."name" is not null)
   and not exists (select 1 from "contribution_sender" s where s."contributionId" = c."id");
