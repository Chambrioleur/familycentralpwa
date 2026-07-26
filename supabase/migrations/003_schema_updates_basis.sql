-- Im SQL Editor ausführen: Geburtstag + Profilbild für Personen ergänzen
alter table members add column if not exists geburtstag date;
alter table members add column if not exists avatar_pfad text;
