  alter table public.users enable row level security;

  create policy "select own user"
  on public.users for select
  using (auth_user_id = auth.uid());

  create policy "update own user"
  on public.users for update
  using (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());