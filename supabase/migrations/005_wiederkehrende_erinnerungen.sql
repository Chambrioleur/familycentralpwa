-- Im SQL Editor ausführen
alter table reminders add column if not exists wiederholung text check (wiederholung in ('taeglich', 'woechentlich', 'monatlich', 'jaehrlich'));
