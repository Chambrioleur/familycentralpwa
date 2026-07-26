-- Im SQL Editor ausführen

-- Wiederholung bei Aufgaben (wie schon bei Erinnerungen) + freier Rhythmus
-- (z.B. "alle 3 Tage" über wiederholung='taeglich' + wiederholung_intervall=3)
alter table tasks add column if not exists wiederholung text check (wiederholung in ('taeglich', 'woechentlich', 'monatlich', 'jaehrlich'));
alter table tasks add column if not exists wiederholung_intervall integer not null default 1;
alter table tasks add column if not exists benachrichtigt_am date;
