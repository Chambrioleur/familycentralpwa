-- Run in the SQL editor

-- Optional monthly budget limit per finance category. NULL means
-- "no limit set" (the default for all existing categories).
alter table finance_categories
  add column if not exists budget_limit numeric(10, 2);
