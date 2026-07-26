-- Im SQL Editor ausführen
alter table tasks alter column wiederholung_intervall drop not null;
alter table tasks alter column wiederholung_intervall drop default;
