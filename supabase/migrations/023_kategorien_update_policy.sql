-- Im SQL Editor ausführen
create policy "finance_categories_update" on finance_categories for update to authenticated
  using (can_edit('finanzen')) with check (can_edit('finanzen'));
