-- Run in the SQL Editor: add birthday + profile picture for people
alter table members add column if not exists geburtstag date;
alter table members add column if not exists avatar_pfad text;
