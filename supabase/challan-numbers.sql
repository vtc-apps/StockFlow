-- ═══════════════════════════════════════════════════════════════════════
--  VTC PGIM · Challan numbers (run once, after stock-accept.sql). Safe to run again.
--
--  Every entry gets a challan number, assigned here so two devices can
--  never issue the same one:
--    Stock Inward / opening : VT26-I-001, VT26-I-002 …  (receiving branch)
--    Stock Transfer         : VT26-T-001, VT26-T-002 …  (sending branch)
--  One series per branch and per financial year (April–March; VT26 = 2026-27).
--  The app shows the expected number; if another device took it first,
--  the next free number is used instead.
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.sf_challan() returns trigger
language plpgsql as $$
declare
  d date;
  fy int;
  pre text;
  mx int;
  want text := coalesce(new.data->>'challanNo', '');
begin
  if exists (select 1 from public.transactions where id = new.id) then
    return new; -- a re-sent entry: the conflict is ignored, nothing to number
  end if;
  begin
    d := (new.data->>'date')::date;
  exception when others then
    return new; -- the entry rules reject a bad date
  end;
  fy := case when extract(month from d) >= 4 then extract(year from d)::int else extract(year from d)::int - 1 end;
  pre := 'VT' || right(fy::text, 2) || '-' || case when new.data->>'type' = 'dispatch' then 'T' else 'I' end || '-';
  perform pg_advisory_xact_lock(hashtext('pgim-challan:' || coalesce(new.data->>'branchId', '') || ':' || pre));
  if want like pre || '%' and substr(want, length(pre) + 1) ~ '^\d+$'
     and not exists (select 1 from public.transactions
                      where data->>'branchId' = new.data->>'branchId' and data->>'challanNo' = want) then
    return new; -- the number the app showed is still free
  end if;
  select coalesce(max(substr(data->>'challanNo', length(pre) + 1)::int), 0) into mx
    from public.transactions
   where data->>'branchId' = new.data->>'branchId'
     and data->>'challanNo' like pre || '%'
     and substr(data->>'challanNo', length(pre) + 1) ~ '^\d+$';
  new.data := new.data || jsonb_build_object('challanNo', pre || case when mx + 1 < 1000 then lpad((mx + 1)::text, 3, '0') else (mx + 1)::text end);
  return new;
end $$;

drop trigger if exists sf_challan on public.transactions;
create trigger sf_challan before insert on public.transactions
  for each row execute function public.sf_challan();

create unique index if not exists transactions_challan_unique
  on public.transactions ((data->>'branchId'), (data->>'challanNo'))
  where data->>'challanNo' is not null;
