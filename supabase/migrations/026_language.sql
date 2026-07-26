-- Run in the SQL Editor.

-- Language choice per person, analogous to theme_praeferenz (017).
-- NULL means "not chosen yet" — the frontend then defaults to German.
alter table members add column if not exists sprache text check (sprache in ('de', 'en'));
