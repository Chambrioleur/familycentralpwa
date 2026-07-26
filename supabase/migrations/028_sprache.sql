-- Im SQL Editor ausführen.

-- Sprachwahl pro Person, analog zu theme_praeferenz (017).
-- NULL bedeutet "noch nicht gewählt" — das Frontend nimmt dann Deutsch.
alter table members add column if not exists sprache text check (sprache in ('de', 'en'));
