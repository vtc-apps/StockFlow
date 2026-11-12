-- ═══════════════════════════════════════════════════════════════════════
--  VTC PGIM · Stock Distribution challan series (VTC26-D-00001). Safe to run again.
--    VTC26-I-…  stock inward / opening
--    VTC26-T-…  stock transfer to a branch
--    VTC26-D-…  stock distribution (shop, salesman, customer, person)
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
  pre := 'VTC' || right(fy::text, 2) || '-' || case when new.data->>'type' <> 'dispatch' then 'I' when coalesce(new.data->>'dispatchType', '') = 'branch_transfer' then 'T' else 'D' end || '-';
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
