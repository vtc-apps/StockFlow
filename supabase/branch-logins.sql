-- ═══════════════════════════════════════════════════════════════════════
--  VTC PGIM · Branch logins + admin "Logins" page (run once, after
--  setup.sql, admin-role.sql and security-update.sql). Safe to run again.
--
--  • app_logins: one row per login (username, password as given, branch).
--    Only admins can read it all; each person can read their own row.
--  • A login with a branch can only record entries for that branch.
--  • Admin functions to add a login, change a password, remove a login.
-- ═══════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.app_logins (
  username    text primary key check (username = lower(username) and username ~ '^[a-z0-9._-]{2,40}$'),
  email       text not null unique,
  password    text not null,
  branch_id   text,
  role        text not null default 'branch' check (role in ('admin', 'staff', 'branch')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.app_logins enable row level security;
revoke all on public.app_logins from anon, authenticated;
grant select on public.app_logins to authenticated;
drop policy if exists sf_read on public.app_logins;
create policy sf_read on public.app_logins for select to authenticated
  using (public.sf_is_admin() or email = lower(coalesce(auth.jwt() ->> 'email', '')));

-- The branch a signed-in person is limited to (null = no limit).
create or replace function public.sf_my_branch() returns text
language sql stable security definer set search_path = public as $$
  select branch_id from public.app_logins
   where email = lower(coalesce(auth.jwt() ->> 'email', '')) and role = 'branch'
$$;
revoke all on function public.sf_my_branch() from public, anon;
grant execute on function public.sf_my_branch() to authenticated;

-- Entry rules (replaces the version from security-update.sql): adds the branch limit.
create or replace function public.sf_entry_rules() returns trigger
language plpgsql as $$
declare
  today date := (now() at time zone 'Asia/Kolkata')::date;
  d date;
  mine text;
begin
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
  return new;
end $$;

-- ── Admin functions (called from the app's Logins page) ────────────────
create or replace function public.pgim_auth_password(p text) returns text
language sql immutable as $$ select case when length(p) < 6 then p || '@pgim' else p end $$;

create or replace function public.pgim_create_login(p_username text, p_password text, p_branch_id text default null, p_role text default 'branch')
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  u text := lower(trim(p_username));
  e text := lower(trim(p_username)) || '@vtc-stockflow.app';
  uid uuid := gen_random_uuid();
begin
  if not public.sf_is_admin() then raise exception 'Only an admin can add logins.' using errcode = '42501'; end if;
  if u !~ '^[a-z0-9._-]{2,40}$' then raise exception 'Username can use letters, numbers, dot, dash and underscore (2–40 characters).' using errcode = 'P0001'; end if;
  if coalesce(length(p_password), 0) < 4 then raise exception 'Password must be at least 4 characters.' using errcode = 'P0001'; end if;
  if p_role not in ('admin', 'staff', 'branch') then raise exception 'Unknown role.' using errcode = 'P0001'; end if;
  if p_role = 'branch' and (p_branch_id is null or not exists (select 1 from public.branches where id = p_branch_id)) then
    raise exception 'Choose the branch for this login.' using errcode = 'P0001';
  end if;
  if exists (select 1 from auth.users where email = e) or exists (select 1 from public.app_logins where username = u) then
    raise exception 'The username % is already taken.', u using errcode = 'P0001';
  end if;
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change, email_change_token_current,
    phone_change, phone_change_token, reauthentication_token, is_sso_user, is_anonymous)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', e,
    crypt(public.pgim_auth_password(p_password), gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{"email_verified":true}', now(), now(),
    '', '', '', '', '', '', '', '', false, false);
  insert into auth.identities (id, user_id, provider, provider_id, identity_data, created_at, updated_at)
  values (gen_random_uuid(), uid, 'email', uid::text,
    jsonb_build_object('sub', uid::text, 'email', e, 'email_verified', true, 'phone_verified', false), now(), now());
  insert into public.app_logins (username, email, password, branch_id, role)
  values (u, e, p_password, case when p_role = 'branch' then p_branch_id end, p_role);
  if p_role = 'admin' then insert into public.app_admins (email) values (e) on conflict do nothing; end if;
end $$;

create or replace function public.pgim_set_password(p_username text, p_password text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare e text;
begin
  if not public.sf_is_admin() then raise exception 'Only an admin can change passwords.' using errcode = '42501'; end if;
  if coalesce(length(p_password), 0) < 4 then raise exception 'Password must be at least 4 characters.' using errcode = 'P0001'; end if;
  select email into e from public.app_logins where username = lower(trim(p_username));
  if e is null then raise exception 'No such login.' using errcode = 'P0001'; end if;
  update auth.users set encrypted_password = crypt(public.pgim_auth_password(p_password), gen_salt('bf')), updated_at = now() where email = e;
  update public.app_logins set password = p_password, updated_at = now() where email = e;
end $$;

create or replace function public.pgim_delete_login(p_username text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare e text; uid uuid;
begin
  if not public.sf_is_admin() then raise exception 'Only an admin can remove logins.' using errcode = '42501'; end if;
  select email into e from public.app_logins where username = lower(trim(p_username));
  if e is null then raise exception 'No such login.' using errcode = 'P0001'; end if;
  if e = lower(coalesce(auth.jwt() ->> 'email', '')) then raise exception 'You can''t remove the login you are using.' using errcode = 'P0001'; end if;
  if e = 'admin@vtc-stockflow.app' then raise exception 'The main admin login can''t be removed.' using errcode = 'P0001'; end if;
  select id into uid from auth.users where email = e;
  if uid is not null then
    delete from auth.sessions where user_id = uid;
    delete from auth.refresh_tokens where user_id = uid::text;
    delete from auth.identities where user_id = uid;
    delete from auth.users where id = uid;
  end if;
  delete from public.app_admins where email = e;
  delete from public.app_logins where email = e;
end $$;

revoke all on function public.pgim_create_login(text, text, text, text) from public, anon;
revoke all on function public.pgim_set_password(text, text) from public, anon;
revoke all on function public.pgim_delete_login(text) from public, anon;
grant execute on function public.pgim_create_login(text, text, text, text) to authenticated;
grant execute on function public.pgim_set_password(text, text) to authenticated;
grant execute on function public.pgim_delete_login(text) to authenticated;
