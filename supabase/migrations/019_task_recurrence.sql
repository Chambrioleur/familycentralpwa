-- Run in the SQL Editor

-- Recurrence for tasks (like reminders already have) + custom interval
-- (e.g. "every 3 days" via wiederholung='taeglich' + wiederholung_intervall=3)
alter table tasks add column if not exists wiederholung text check (wiederholung in ('taeglich', 'woechentlich', 'monatlich', 'jaehrlich'));
alter table tasks add column if not exists wiederholung_intervall integer not null default 1;
alter table tasks add column if not exists benachrichtigt_am date;
