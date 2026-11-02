-- ═══════════════════════════════════════════════════════════════════════
--  VTC PGIM · Stock Accept (run once, after branch-logins.sql). Safe to run again.
--
--  A stock transfer sent by a branch (or staff) login is "pending" until the
--  receiving branch accepts it:
--    pending  → stock has left the sender, not yet added to the receiver
--    accepted → added to the receiver
--    declined → cancelled; the stock stays with the sender
--  Transfers made by an admin arrive straight away (no status).
-- ═══════════════════════════════════════════════════════════════════════

-- ── Stock check that understands pending / declined transfers ──────────
create or replace function public.sf_check_stock(p_product text, p_branch text) returns void
language plpgsql as $$
declare
  v_date text;
  v_bal  numeric;
  v_pname text;
  v_bname text;
begin
  if p_product is null or p_branch is null then return; end if;

  with mv as (
    select t.data->>'date' as d,
           case t.data->>'type' when 'opening' then 0 when 'inward' then 1 else 2 end as ord,
           coalesce((t.data->>'createdAt')::numeric, 0) as ca,
           t.id,
           case
             when t.data->>'type' in ('opening', 'inward') and t.data->>'branchId' = p_branch
               then (t.data->>'quantity')::numeric
             when t.data->>'type' = 'dispatch' and t.data->>'branchId' = p_branch
                  and coalesce(t.data->>'transferStatus', '') <> 'declined'
               then -(t.data->>'quantity')::numeric
             else 0
           end
           + case
               when t.data->>'type' = 'dispatch' and t.data->>'dispatchType' = 'branch_transfer'
                    and t.data->>'destinationBranchId' = p_branch
                    and coalesce(t.data->>'transferStatus', 'accepted') = 'accepted'
                 then (t.data->>'quantity')::numeric
               else 0
             end as delta
      from public.transactions t
     where t.data->>'productId' = p_product
       and (t.data->>'branchId' = p_branch or t.data->>'destinationBranchId' = p_branch)
  ),
  run as (
    select d, sum(delta) over (order by d, ord, ca, id collate "C" rows unbounded preceding) as bal
      from mv
  )
  select d, bal into v_date, v_bal from run where bal < 0 order by d limit 1;

  if v_date is not null then
    select data->>'name' into v_pname from public.products where id = p_product;
    select data->>'name' into v_bname from public.branches where id = p_branch;
    raise exception 'Not enough stock: % at % would fall to % on %. Stock can never go negative.',
      coalesce(v_pname, 'this product'), coalesce(v_bname, 'this branch'), v_bal,
      to_char(v_date::date, 'DD-MM-YYYY')
      using errcode = 'P0001';
  end if;
end $$;

-- ── Entry rules: non-admin transfers start as pending ───────────────────
create or replace function public.sf_entry_rules() returns trigger
language plpgsql as $$
declare
  today date := (now() at time zone 'Asia/Kolkata')::date;
  d date;
  mine text;
begin
  -- accept / decline goes through pgim_respond_transfer, which checks its own rules
  if tg_op = 'UPDATE' and current_setting('pgim.respond', true) = '1' then
    return new;
  end if;
  if tg_op = 'INSERT' and exists (select 1 from public.transactions where id = new.id) then
    return new;
  end if;
  begin
    d := (new.data->>'date')::date;
  exception when others then
    raise exception 'The entry date is not valid.' using errcode = 'P0001';
  end;
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
  mine := public.sf_my_branch();
  if mine is not null and new.data->>'branchId' is distinct from mine then
    raise exception 'This login can only record entries for its own branch.' using errcode = 'P0001';
  end if;
  if new.data->>'dispatchType' = 'branch_transfer' then
    new.data := (new.data - 'respondedAt' - 'respondedBy' - 'responseNote') || '{"transferStatus":"pending"}'::jsonb;
  end if;
  return new;
end $$;

-- ── Accept / decline (receiving branch login, or an admin) ──────────────
create or replace function public.pgim_respond_transfer(p_id text, p_accept boolean, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  t jsonb;
  mine text := public.sf_my_branch();
  admin boolean := public.sf_is_admin();
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  name text;
  upd jsonb;
  log_id text := 'log-xfer-' || p_id || '-' || (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  select data into t from public.transactions where id = p_id for update;
  if t is null then raise exception 'This transfer no longer exists.' using errcode = 'P0001'; end if;
  if coalesce(t->>'transferStatus', '') <> 'pending' then
    raise exception 'This transfer has already been %.', coalesce(t->>'transferStatus', 'received') using errcode = 'P0001';
  end if;
  if not admin and (mine is null or mine <> t->>'destinationBranchId') then
    raise exception 'Only the receiving branch can accept or decline this stock.' using errcode = '42501';
  end if;
  name := case when who like '%@vtc-stockflow.app' then split_part(who, '@', 1) else who end;
  upd := t || jsonb_build_object(
    'transferStatus', case when p_accept then 'accepted' else 'declined' end,
    'respondedAt', (extract(epoch from now()) * 1000)::bigint,
    'respondedBy', name,
    'responseNote', coalesce(trim(p_note), ''),
    'updatedAt', (extract(epoch from now()) * 1000)::bigint);
  perform set_config('pgim.respond', '1', true);
  update public.transactions set data = upd where id = p_id;
  perform set_config('pgim.respond', '', true);
  insert into public.change_log (id, data) values (
    log_id,
    jsonb_build_object(
      'id', log_id,
      'at', (extract(epoch from now()) * 1000)::bigint,
      'by', name, 'action', 'edit', 'entity', 'transaction', 'entityId', p_id,
      'label', 'Transfer ' || p_id,
      'changes', jsonb_build_array(jsonb_build_object('field', 'Stock transfer', 'from', 'Pending', 'to', case when p_accept then 'Accepted' else 'Declined' end))
        || case when coalesce(trim(p_note), '') <> '' then jsonb_build_array(jsonb_build_object('field', 'Note', 'from', '—', 'to', trim(p_note))) else '[]'::jsonb end));
  return upd;
end $$;

revoke all on function public.pgim_respond_transfer(text, boolean, text) from public, anon;
grant execute on function public.pgim_respond_transfer(text, boolean, text) to authenticated;
