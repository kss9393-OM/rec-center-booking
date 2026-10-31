-- ============================================================
-- Two more management roles, and team notes between management accounts.
-- © 2026 Services Squire LLC. All rights reserved.
--
--   staff      reception: check-ins, scanning, student messages, reports
--   admin      everything a reception account does, plus settings, accounts and students
--   developer  everything an admin does, plus the center name and logo,
--              and sending alerts to supervisors and the main admin
--   viewer     follow-up only: statistics and bookings (read-only), and sending
--              messages to supervisors and the main admin. Cannot change anything.
-- ============================================================

alter table public.staff drop constraint if exists staff_role_check;
alter table public.staff add constraint staff_role_check check (role in ('staff', 'admin', 'developer', 'viewer'));

-- Any management account that may change data (everyone except viewers).
create or replace function public.is_operator() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff where id = auth.uid() and active and role <> 'viewer');
$$;
create or replace function public.is_developer() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff where id = auth.uid() and active and role = 'developer');
$$;
grant execute on function public.is_operator() to anon, authenticated;
grant execute on function public.is_developer() to anon, authenticated;

-- Admin checks also accept developers; "any staff" write checks exclude viewers.
do $$
declare f record; src text; out text;
begin
  for f in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in
      ('is_admin', 'needs_bootstrap', 'admin_warn', 'admin_restrict', 'admin_delete_warning',
       'desk_mark', 'scan_ticket', 'verify_student', 'mark_alerts_read', 'mark_thread_seen')
  loop
    src := pg_get_functiondef(f.oid);
    out := replace(src, 'role = ''admin''', 'role in (''admin'', ''developer'')');
    out := replace(out, 'from staff where id = auth.uid() and active;', 'from staff where id = auth.uid() and active and role <> ''viewer'';');
    out := replace(out, 'if not is_staff() then', 'if not is_operator() then');
    if out <> src then execute out; end if;
  end loop;
end $$;

-- Viewers don't read or write student conversations.
drop policy if exists messages_read on public.messages;
create policy messages_read on public.messages for select using (student = auth.uid() or public.is_operator());
drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages for insert with check (
  (from_role = 'student' and student = auth.uid() and read = true)
  or (from_role = 'staff' and public.is_operator())
);
drop policy if exists threads_read on public.threads;
create policy threads_read on public.threads for select using (public.is_operator());

-- Only the developer changes the center name and logo.
create or replace function public._guard_identity() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null
     and ((new.data -> 'name') is distinct from (old.data -> 'name') or (new.data -> 'logo') is distinct from (old.data -> 'logo'))
     and not public.is_developer() then
    raise exception 'developer_only';
  end if;
  return new;
end $$;
drop trigger if exists config_identity_guard on public.config;
create trigger config_identity_guard before update on public.config for each row execute function public._guard_identity();

-- Team notes travel through the alerts list.
--   notice   : an alert sent by the developer
--   team_msg : a message sent by any other management account (e.g. a viewer)
alter table public.alerts drop constraint if exists alerts_kind_check;
alter table public.alerts add constraint alerts_kind_check check (kind in ('no_show', 'auto_warning', 'notice', 'team_msg'));
alter table public.alerts add column if not exists from_id uuid;
alter table public.alerts add column if not exists from_name text not null default '';
alter table public.alerts add column if not exists from_role text not null default '';
alter table public.alerts add column if not exists audience text not null default 'all';
alter table public.alerts drop constraint if exists alerts_audience_check;
alter table public.alerts add constraint alerts_audience_check check (audience in ('all', 'admin'));

drop policy if exists alerts_read on public.alerts;
create policy alerts_read on public.alerts for select
  using (public.is_staff() and (audience = 'all' or public.is_admin() or from_id = auth.uid()));

create or replace function public.send_team_note(p_text text, p_audience text)
returns bigint language plpgsql security definer set search_path = public as $$
declare me staff; nid bigint;
begin
  select * into me from staff where id = auth.uid() and active;
  if not found then raise exception 'forbidden'; end if;
  if coalesce(trim(p_text), '') = '' then raise exception 'bad_text'; end if;
  if p_audience not in ('all', 'admin') then raise exception 'bad_audience'; end if;
  insert into alerts (kind, text, from_id, from_name, from_role, audience)
  values (case when me.role = 'developer' then 'notice' else 'team_msg' end, left(trim(p_text), 1000),
          me.id, me.name, me.role, p_audience)
  returning id into nid;
  return nid;
end $$;
revoke execute on function public.send_team_note(text, text) from public, anon;
grant execute on function public.send_team_note(text, text) to authenticated;

-- Read state: automatic alerts are handled once for everyone (read_at);
-- team notes are read per person (alert_reads).
create table if not exists public.alert_reads (
  alert_id bigint not null references public.alerts (id) on delete cascade,
  staff_id uuid not null references public.staff (id) on delete cascade,
  at timestamptz not null default now(),
  primary key (alert_id, staff_id)
);
alter table public.alert_reads enable row level security;
drop policy if exists alert_reads_own on public.alert_reads;
create policy alert_reads_own on public.alert_reads for select using (staff_id = auth.uid());

create or replace function public.mark_alerts_read(p_ids bigint[])
returns void language plpgsql security definer set search_path = public as $$
declare me staff;
begin
  select * into me from staff where id = auth.uid() and active;
  if not found then raise exception 'forbidden'; end if;
  -- team notes: per person (viewers too)
  insert into alert_reads (alert_id, staff_id)
  select a.id, me.id from alerts a
  where a.kind in ('notice', 'team_msg') and (p_ids is null or a.id = any (p_ids))
    and a.from_id is distinct from me.id
    and (a.audience = 'all' or me.role in ('admin', 'developer'))
  on conflict do nothing;
  -- automatic alerts: once for everyone (not by viewers)
  if me.role <> 'viewer' then
    update alerts set read_at = now(), read_by = me.name
    where read_at is null and kind in ('no_show', 'auto_warning') and (p_ids is null or id = any (p_ids));
  end if;
end $$;

do $$ begin
  begin alter publication supabase_realtime add table public.alert_reads; exception when others then null; end;
end $$;
