-- ═══════════════════════════════════════════════════════════════════════
--  VTC PGIM · Challan numbers (run once, after stock-accept.sql). Safe to run again.
--
--  Every entry gets a challan number, assigned here so two devices can
--  never issue the same one:
--    Stock Inward / opening : VTC26-I-00001, VTC26-I-00002 …
--    Stock Transfer         : VTC26-T-00001, VTC26-T-00002 …
--  One company-wide series each (all branches), per financial year
--  (April–March; VTC26 = 2026-27). Products saved together in one entry
--  (same challanGroup) share one number; separate entries never share one.
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
  grp text := nullif(new.data->>'challanGroup', '');
  grp_no text;
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
  pre := 'VTC' || right(fy::text, 2) || '-' || case when new.data->>'type' = 'dispatch' then 'T' else 'I' end || '-';
  perform pg_advisory_xact_lock(hashtext('pgim-challan:' || pre));
  -- another product of the same entry is already saved: use its number
  if grp is not null then
    select data->>'challanNo' into grp_no from public.transactions
     where data->>'challanGroup' = grp and data->>'challanNo' like pre || '%' limit 1;
    if grp_no is not null then
      new.data := new.data || jsonb_build_object('challanNo', grp_no);
      return new;
    end if;
  end if;
  if want like pre || '%' and substr(want, length(pre) + 1) ~ '^\d+$'
     and not exists (select 1 from public.transactions
                      where data->>'challanNo' = want and coalesce(data->>'challanGroup', '') <> coalesce(grp, '-')) then
    return new; -- the number the app showed is still free
  end if;
  select coalesce(max(substr(data->>'challanNo', length(pre) + 1)::int), 0) into mx
    from public.transactions
   where data->>'challanNo' like pre || '%'
     and substr(data->>'challanNo', length(pre) + 1) ~ '^\d+$';
  new.data := new.data || jsonb_build_object('challanNo', pre || case when mx + 1 < 100000 then lpad((mx + 1)::text, 5, '0') else (mx + 1)::text end);
  return new;
end $$;

drop trigger if exists sf_challan on public.transactions;
create trigger sf_challan before insert on public.transactions
  for each row execute function public.sf_challan();

-- one number can now cover several products of one entry, so it is no longer a unique index
drop index if exists public.transactions_challan_unique;
drop index if exists public.transactions_challan_no_unique;
create index if not exists transactions_challan_no_idx on public.transactions ((data->>'challanNo'));
