-- ============================================================
-- Student moderation (system admins only): restrictions and warnings.
-- © 2026 Services Squire LLC. All rights reserved.
-- Run after schema.sql (already included in schema.sql for new projects).
-- ============================================================

alter table public.students add column if not exists restricted boolean not null default false;
alter table public.students add column if not exists restricted_until date;
alter table public.students add column if not exists restrict_reason text not null default '';

create table if not exists public.warnings (
  id bigint generated always as identity primary key,
  student uuid not null references auth.users (id) on delete cascade,
  reason text not null check (length(reason) between 1 and 500),
  by_name text not null default '',
  at timestamptz not null default now()
);
create index if not exists warnings_student_idx on public.warnings (student, at desc);
alter table public.warnings enable row level security;
drop policy if exists warnings_read on public.warnings;
create policy warnings_read on public.warnings for select using (student = auth.uid() or public.is_staff());

-- A restriction is in force when set and not yet past its end date (center time).
create or replace function public._is_restricted(p_student uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select restricted and (restricted_until is null
      or restricted_until >= (now() at time zone coalesce((select data ->> 'tz' from config where id = 1), 'Asia/Muscat'))::date)
    from students where id = p_student), false);
$$;

-- Booking and changing a booking are refused while restricted.
create or replace function public.book(p_date text, p_slot int, p_section text)
returns public.bookings language plpgsql security definer set search_path = public as $$
declare
  st students; cap int; v_id text; ex bookings; r bookings;
begin
  select * into st from students where id = auth.uid();
  if not found then raise exception 'no_student'; end if;
  if _is_restricted(st.id) then raise exception 'restricted'; end if;
  cap := _check_slot(p_date, p_slot, p_section);
  perform pg_advisory_xact_lock(hashtext('crc:' || p_date));
  v_id := p_date || '_' || st.sid;
  select * into ex from bookings where id = v_id;
  if found and ex.status <> 'cancelled' then raise exception 'dup'; end if;
  if _taken(p_date, p_slot, p_section) >= cap then raise exception 'full'; end if;
  insert into bookings (id, code, date, slot_id, section, student_id, student_name, uid, status)
  values (v_id, 'CRC-' || substr(p_date, 1, 4) || '-' || _rand4(), p_date, p_slot, p_section, st.sid, st.name, auth.uid(), 'booked')
  on conflict (id) do update set
    code = excluded.code, slot_id = excluded.slot_id, section = excluded.section,
    student_name = excluded.student_name, uid = excluded.uid, status = 'booked',
    desk_status = null, desk_by = null, desk_by_name = null, desk_at = null,
    created_at = now(), edited_at = null, cancelled_at = null
  returning * into r;
  return r;
end $$;

create or replace function public.move_booking(p_id text, p_slot int, p_section text)
returns public.bookings language plpgsql security definer set search_path = public as $$
declare
  b bookings; cap int; r bookings;
begin
  if _is_restricted(auth.uid()) then raise exception 'restricted'; end if;
  select * into b from bookings where id = p_id and uid = auth.uid();
  if not found then raise exception 'not_found'; end if;
  if b.status <> 'booked' or b.desk_status is not null then raise exception 'locked'; end if;
  cap := _check_slot(b.date, p_slot, p_section);
  perform pg_advisory_xact_lock(hashtext('crc:' || b.date));
  if _taken(b.date, p_slot, p_section, p_id) >= cap then raise exception 'full'; end if;
  update bookings set slot_id = p_slot, section = p_section, edited_at = now() where id = p_id returning * into r;
  return r;
end $$;

-- Restrict / lift (system admin). Restricting also cancels the student's upcoming bookings
-- and sends them a message with the reason.
create or replace function public.admin_restrict(p_student uuid, p_on boolean, p_until date, p_reason text)
returns int language plpgsql security definer set search_path = public as $$
declare me staff; n int := 0; tz text; txt text;
begin
  select * into me from staff where id = auth.uid() and active and role = 'admin';
  if not found then raise exception 'forbidden'; end if;
  if not exists (select 1 from students where id = p_student) then raise exception 'not_found'; end if;
  tz := coalesce((select data ->> 'tz' from config where id = 1), 'Asia/Muscat');
  if p_on then
    update students set restricted = true, restricted_until = p_until, restrict_reason = left(coalesce(trim(p_reason), ''), 500)
    where id = p_student;
    update bookings set status = 'cancelled', cancelled_at = now()
    where uid = p_student and status = 'booked' and desk_status is null
      and date >= to_char((now() at time zone tz)::date, 'YYYY-MM-DD');
    get diagnostics n = row_count;
    txt := 'تم تقييد حسابك من الحجز' || case when p_until is not null then ' حتى ' || to_char(p_until, 'YYYY-MM-DD') else '' end
        || case when coalesce(trim(p_reason), '') <> '' then '. السبب: ' || trim(p_reason) else '' end
        || E'\nYour booking access has been restricted'
        || case when p_until is not null then ' until ' || to_char(p_until, 'YYYY-MM-DD') else '' end || '.';
  else
    update students set restricted = false, restricted_until = null, restrict_reason = '' where id = p_student;
    txt := E'تم رفع التقييد عن حسابك ويمكنك الحجز مجدداً.\nYour booking access has been restored.';
  end if;
  insert into messages (student, text, from_role, by_name, by_user) values (p_student, txt, 'staff', me.name, me.username);
  return n;
end $$;

-- Formal warning (system admin): recorded in the student's history and sent as a message.
create or replace function public.admin_warn(p_student uuid, p_reason text)
returns int language plpgsql security definer set search_path = public as $$
declare me staff; total int;
begin
  select * into me from staff where id = auth.uid() and active and role = 'admin';
  if not found then raise exception 'forbidden'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'bad_reason'; end if;
  if not exists (select 1 from students where id = p_student) then raise exception 'not_found'; end if;
  insert into warnings (student, reason, by_name) values (p_student, left(trim(p_reason), 500), me.name);
  select count(*) into total from warnings where student = p_student;
  insert into messages (student, text, from_role, by_name, by_user)
  values (p_student, '⚠️ إنذار رسمي رقم ' || total || ': ' || trim(p_reason) || E'\n⚠️ Formal warning #' || total || '.', 'staff', me.name, me.username);
  return total;
end $$;

create or replace function public.admin_delete_warning(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  delete from warnings where id = p_id;
end $$;

-- Permissions
revoke execute on function public._is_restricted(uuid) from public, anon, authenticated;
revoke execute on function public.admin_restrict(uuid, boolean, date, text) from public, anon;
revoke execute on function public.admin_warn(uuid, text) from public, anon;
revoke execute on function public.admin_delete_warning(bigint) from public, anon;
grant execute on function public.admin_restrict(uuid, boolean, date, text) to authenticated;
grant execute on function public.admin_warn(uuid, text) to authenticated;
grant execute on function public.admin_delete_warning(bigint) to authenticated;
revoke execute on function public.book(text, int, text) from public, anon;
revoke execute on function public.move_booking(text, int, text) from public, anon;
grant execute on function public.book(text, int, text) to authenticated;
grant execute on function public.move_booking(text, int, text) to authenticated;

do $$ begin
  begin alter publication supabase_realtime add table public.warnings; exception when others then null; end;
  begin alter publication supabase_realtime add table public.students; exception when others then null; end;
end $$;
