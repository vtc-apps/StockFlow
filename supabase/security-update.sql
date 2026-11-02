-- ═══════════════════════════════════════════════════════════════════════
--  VTC PGIM · Security update (run once in Supabase → SQL Editor,
--  after setup.sql and admin-role.sql). Safe to run again.
--
--  1. Change Log: only admins can add records, and the database itself
--     writes who made each change (it can't be typed in by hand).
--  2. Entry dates: nobody can date an entry in the future; staff can date
--     entries up to 7 days back; only admins can record opening stock.
-- ═══════════════════════════════════════════════════════════════════════

-- ── 1. Change Log ───────────────────────────────────────────────────────
drop policy if exists sf_insert on public.change_log;
create policy sf_insert on public.change_log for insert to authenticated
  with check (public.sf_is_admin());

create or replace function public.sf_log_stamp() returns trigger
language plpgsql as $$
declare
  e text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if e <> '' then
    new.data := new.data || jsonb_build_object(
      'by', case when e like '%@vtc-stockflow.app' then split_part(e, '@', 1) else e end,
      'byEmail', e
    );
  end if;
  new.created_by := auth.uid();
  new.created_at := now();
  return new;
end $$;

drop trigger if exists sf_log_stamp on public.change_log;
create trigger sf_log_stamp before insert on public.change_log
  for each row execute function public.sf_log_stamp();

-- ── 2. Entry date rules ─────────────────────────────────────────────────
create or replace function public.sf_entry_rules() returns trigger
language plpgsql as $$
declare
  today date := (now() at time zone 'Asia/Kolkata')::date;
  d date;
begin
  -- re-sending an entry the server already has (a retry) is not a new entry
  if tg_op = 'INSERT' and exists (select 1 from public.transactions where id = new.id) then
    return new;
  end if;
  begin
    d := (new.data->>'date')::date;
  exception when others then
    raise exception 'The entry date is not valid.' using errcode = 'P0001';
  end;
  -- one day of grace for a device clock that is slightly ahead
  if d > today + 1 then
    raise exception 'Entries can''t be dated in the future (%).', to_char(d, 'DD-MM-YYYY') using errcode = 'P0001';
  end if;
  if public.sf_is_admin() then
    return new;
  end if;
  if new.data->>'type' = 'opening' then
    raise exception 'Only an admin can record opening stock.' using errcode = 'P0001';
  end if;
  if d < today - 7 then
    raise exception 'Staff can date entries up to 7 days back (this one is dated %). Ask an admin to record it.', to_char(d, 'DD-MM-YYYY') using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists sf_entry_rules on public.transactions;
create trigger sf_entry_rules before insert or update on public.transactions
  for each row execute function public.sf_entry_rules();
