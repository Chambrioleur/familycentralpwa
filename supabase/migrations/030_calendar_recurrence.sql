-- Run in the SQL editor

-- Exceptions within a recurring event series (e.g. "delete just this one
-- event from the weekly series" without ending the whole series). Holds
-- the original start times of the skipped occurrences.
alter table calendar_events
  add column if not exists rrule_exdates timestamptz[] not null default '{}';
