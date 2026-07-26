-- Run in the SQL Editor
alter table tasks alter column wiederholung_intervall drop not null;
alter table tasks alter column wiederholung_intervall drop default;
