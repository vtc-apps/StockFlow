-- ═══════════════════════════════════════════════════════════════════════
--  VTC PGIM · Admin role (run once in Supabase → SQL Editor, after setup.sql)
--
--  • admin  (admin@vtc-stockflow.app, plus anyone added to app_admins):
--      can delete inward / outward / transfer entries, edit entries, and
--      manage products, branches and settings.
--  • everyone else: can record new entries only.
--  Deleting an entry is still refused if later entries depend on that stock.
--  Products, branches, settings and the change log still can never be deleted.
--  Safe to run again.
-- ═══════════════════════════════════════════════════════════════════════

-- ── Who is an admin ─────────────────────────────────────────────────────
create table if not exists public.app_admins (
  email text primary key check (email = lower(email))
);
insert into public.app_admins (email) values ('admin@vtc-stockflow.app') on conflict do nothing;

alter table public.app_admins enable row level security;
revoke all on public.app_admins from anon, authenticated;
grant select on public.app_admins to authenticated;
drop policy if exists sf_read on public.app_admins;
create policy sf_read on public.app_admins for select to authenticated using (true);

create or replace function public.sf_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.app_admins a
     where a.email = lower(coalesce(auth.jwt() ->> 'email', ''))
  )
$$;
revoke all on function public.sf_is_admin() from public, anon;
grant execute on function public.sf_is_admin() to authenticated;

-- ── Entries: only an admin may delete ───────────────────────────────────
create or replace function public.sf_delete_entry_admin_only() returns trigger
language plpgsql as $$
begin
  if public.sf_is_admin() then
    return old;
  end if;
  raise exception 'Only an admin can delete entries.' using errcode = 'P0001';
end $$;

drop trigger if exists sf_no_delete on public.transactions;
create trigger sf_no_delete before delete on public.transactions
  for each row execute function public.sf_delete_entry_admin_only();

-- Re-check stock after an entry is added, changed or deleted.
create or replace function public.sf_transactions_check() returns trigger
language plpgsql as $$
begin
  if tg_op in ('INSERT', 'UPDATE') then
    perform pg_advisory_xact_lock(hashtext('sf:' || (new.data->>'productId')));
    perform public.sf_check_stock(new.data->>'productId', new.data->>'branchId');
    if new.data->>'dispatchType' = 'branch_transfer' then
      perform public.sf_check_stock(new.data->>'productId', new.data->>'destinationBranchId');
    end if;
  end if;
  if tg_op in ('UPDATE', 'DELETE') then
    perform pg_advisory_xact_lock(hashtext('sf:' || (old.data->>'productId')));
    perform public.sf_check_stock(old.data->>'productId', old.data->>'branchId');
    if old.data->>'dispatchType' = 'branch_transfer' then
      perform public.sf_check_stock(old.data->>'productId', old.data->>'destinationBranchId');
    end if;
  end if;
  return null;
end $$;

drop trigger if exists sf_transactions_check on public.transactions;
create trigger sf_transactions_check after insert or update or delete on public.transactions
  for each row execute function public.sf_transactions_check();

grant delete on public.transactions to authenticated;

drop policy if exists sf_update on public.transactions;
drop policy if exists sf_delete on public.transactions;
create policy sf_update on public.transactions for update to authenticated
  using (public.sf_is_admin()) with check (public.sf_is_admin());
create policy sf_delete on public.transactions for delete to authenticated
  using (public.sf_is_admin());

-- ── Products, branches, settings: admin only ────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['products', 'branches', 'settings'] loop
    execute format('drop policy if exists sf_insert on public.%I', t);
    execute format('drop policy if exists sf_update on public.%I', t);
    execute format('create policy sf_insert on public.%I for insert to authenticated with check (public.sf_is_admin())', t);
    execute format('create policy sf_update on public.%I for update to authenticated using (public.sf_is_admin()) with check (public.sf_is_admin())', t);
  end loop;
end $$;

-- Done. Next: Authentication → Users → Add user
--   Email: admin@vtc-stockflow.app   Password: admin@pgim   (tick Auto Confirm User)
--   Staff then sign in to PGIM with username "admin" and password "admin".
