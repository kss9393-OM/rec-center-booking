-- ============================================================
-- Campus Recreation Center Booking — Supabase schema
-- © 2026 Services Squire LLC. All rights reserved.
--
-- Run this whole file once in Supabase: SQL Editor → New query → Run.
-- ============================================================

-- ---------- Tables ----------

-- Center settings (one row). Seeded with the default zones and hours.
create table if not exists public.config (
  id int primary key default 1 check (id = 1),
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

insert into public.config (id, data) values (1, '{
  "tz": "Asia/Muscat",
  "name": {"ar": "مركز الترفيه الطلابي", "en": "Campus Recreation Center"},
  "logo": "",
  "sections": [
    {"id": "ps", "icon": "ps", "cap": 10, "ar": "بلايستيشن", "en": "PlayStation"},
    {"id": "billiards", "icon": "billiards", "cap": 20, "ar": "البلياردو", "en": "Billiards"},
    {"id": "tt", "icon": "tt", "cap": 4, "ar": "تنس الطاولة", "en": "Table Tennis"},
    {"id": "carrom", "icon": "carrom", "cap": 4, "ar": "الكيرم", "en": "Carrom"},
    {"id": "foosball", "icon": "foosball", "cap": 2, "ar": "كرة الطاولة (فوسبول)", "en": "Foosball"},
    {"id": "cards", "icon": "cards", "cap": 5, "ar": "ألعاب الورق", "en": "Solitaire / Cards"},
    {"id": "other", "icon": "other", "cap": 5, "ar": "ألعاب أخرى", "en": "Other Games"}
  ],
  "slots": [
    {"id": 1, "shift": "m", "s": "07:30", "e": "08:30"},
    {"id": 2, "shift": "m", "s": "08:30", "e": "09:30"},
    {"id": 3, "shift": "m", "s": "09:30", "e": "10:30"},
    {"id": 4, "shift": "m", "s": "10:30", "e": "11:30"},
    {"id": 5, "shift": "e", "s": "16:30", "e": "17:30"},
    {"id": 6, "shift": "e", "s": "17:30", "e": "18:30"},
    {"id": 7, "shift": "e", "s": "18:30", "e": "19:30"},
    {"id": 8, "shift": "e", "s": "19:30", "e": "20:30"}
  ],
  "weeklyOff": [],
  "closed": []
}'::jsonb)
on conflict (id) do nothing;

-- Management accounts (reception staff and system admins).
-- Rows are created only by the "admin" edge function.
create table if not exists public.staff (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  name text not null,
  role text not null default 'staff' check (role in ('staff', 'admin')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Student accounts. Username = student ID.
create table if not exists public.students (
  id uuid primary key references auth.users (id) on delete cascade,
  sid text not null unique check (sid ~ '^[0-9]{4,12}$'),
  name text not null check (length(name) between 3 and 120),
  college text not null default '',
  phone text not null default '',
  must_change boolean not null default false,
  created_at timestamptz not null default now()
);

-- Bookings. id = '<YYYY-MM-DD>_<student id>' so a student can hold one per day.
create table if not exists public.bookings (
  id text primary key,
  code text not null,
  date text not null check (date ~ '^\d{4}-\d{2}-\d{2}$'),
  slot_id int not null,
  section text not null,
  student_id text not null,
  student_name text not null,
  uid uuid not null references auth.users (id) on delete cascade,
  status text not null default 'booked' check (status in ('booked', 'cancelled')),
  desk_status text check (desk_status in ('checked-in', 'no-show')),
  desk_by text,
  desk_by_name text,
  desk_at timestamptz,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  cancelled_at timestamptz
);
create index if not exists bookings_date_idx on public.bookings (date);
create index if not exists bookings_student_idx on public.bookings (student_id);

-- Messages between a student and the center staff.
create table if not exists public.messages (
  id bigint generated always as identity primary key,
  student uuid not null references auth.users (id) on delete cascade,
  text text not null check (length(text) between 1 and 2000),
  from_role text not null check (from_role in ('staff', 'student')),
  by_name text not null default '',
  by_user text not null default '',
  code text not null default '',
  read boolean not null default false,
  at timestamptz not null default now()
);
create index if not exists messages_student_idx on public.messages (student, at desc);

-- One row per conversation, maintained by a trigger; staff browse this list.
create table if not exists public.threads (
  student uuid primary key references auth.users (id) on delete cascade,
  sid text,
  name text,
  last_at timestamptz,
  last_text text,
  last_from text,
  staff_seen_at timestamptz not null default 'epoch'
);

-- ---------- Helpers ----------

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff where id = auth.uid() and active);
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff where id = auth.uid() and active and role = 'admin');
$$;

create or replace function public._rand4() returns text
language sql volatile set search_path = public as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '')
  from generate_series(1, 4);
$$;

-- Validates a date/hour/zone against the settings; returns the zone capacity.
create or replace function public._check_slot(p_date text, p_slot int, p_section text)
returns int language plpgsql stable security definer set search_path = public as $$
declare
  cfg jsonb; tz text; sl jsonb; cap int;
begin
  select data into cfg from config where id = 1;
  tz := coalesce(cfg ->> 'tz', 'Asia/Muscat');
  if p_date !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_date'; end if;
  if exists (select 1 from jsonb_array_elements(coalesce(cfg -> 'closed', '[]')) c where c ->> 'date' = p_date)
     or coalesce(cfg -> 'weeklyOff', '[]') @> to_jsonb(extract(dow from p_date::date)::int) then
    raise exception 'closed_day';
  end if;
  select s into sl from jsonb_array_elements(coalesce(cfg -> 'slots', '[]')) s where (s ->> 'id')::int = p_slot;
  if sl is null then raise exception 'bad_slot'; end if;
  select (s ->> 'cap')::int into cap from jsonb_array_elements(coalesce(cfg -> 'sections', '[]')) s where s ->> 'id' = p_section;
  if cap is null then raise exception 'bad_section'; end if;
  -- booking stays open until 10 minutes after the hour starts
  if ((p_date || ' ' || (sl ->> 's'))::timestamp at time zone tz) + interval '10 minutes' < now() then
    raise exception 'slot_closed';
  end if;
  if p_date::date > (now() at time zone tz)::date + 14 then raise exception 'too_far'; end if;
  return cap;
end $$;

-- Seats taken: booked or checked in (no-shows release the seat).
create or replace function public._taken(p_date text, p_slot int, p_section text, p_except text default '')
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from bookings
  where date = p_date and slot_id = p_slot and section = p_section
    and status = 'booked' and coalesce(desk_status, '') <> 'no-show' and id <> p_except;
$$;

-- ---------- Student actions ----------

create or replace function public.book(p_date text, p_slot int, p_section text)
returns public.bookings language plpgsql security definer set search_path = public as $$
declare
  st students; cap int; v_id text; ex bookings; r bookings;
begin
  select * into st from students where id = auth.uid();
  if not found then raise exception 'no_student'; end if;
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
  select * into b from bookings where id = p_id and uid = auth.uid();
  if not found then raise exception 'not_found'; end if;
  if b.status <> 'booked' or b.desk_status is not null then raise exception 'locked'; end if;
  cap := _check_slot(b.date, p_slot, p_section);
  perform pg_advisory_xact_lock(hashtext('crc:' || b.date));
  if _taken(b.date, p_slot, p_section, p_id) >= cap then raise exception 'full'; end if;
  update bookings set slot_id = p_slot, section = p_section, edited_at = now() where id = p_id returning * into r;
  return r;
end $$;

create or replace function public.cancel_booking(p_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update bookings set status = 'cancelled', cancelled_at = now()
  where id = p_id and uid = auth.uid() and status = 'booked' and desk_status is null;
  if not found then raise exception 'locked'; end if;
end $$;

-- Seat counts for a day; anyone may read counts, never names.
create or replace function public.availability(p_date text)
returns table (slot_id int, section text, eff text, own_id text, n int)
language sql stable security definer set search_path = public as $$
  select b.slot_id, b.section,
         case when b.desk_status = 'checked-in' then 'checked-in' else 'booked' end,
         case when b.uid = auth.uid() then b.id end,
         count(*)::int
  from bookings b
  where b.date = p_date and b.status = 'booked' and coalesce(b.desk_status, '') <> 'no-show'
  group by 1, 2, 3, 4;
$$;

create or replace function public.update_profile(p_name text, p_college text, p_phone text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if length(trim(p_name)) < 3 then raise exception 'bad_name'; end if;
  update students set name = trim(p_name), college = left(trim(coalesce(p_college, '')), 120),
    phone = left(trim(coalesce(p_phone, '')), 30)
  where id = auth.uid();
end $$;

create or replace function public.clear_must_change()
returns void language sql security definer set search_path = public as $$
  update students set must_change = false where id = auth.uid();
$$;

create or replace function public.mark_read(p_id bigint)
returns void language sql security definer set search_path = public as $$
  update messages set read = true where id = p_id and student = auth.uid() and from_role = 'staff';
$$;

-- ---------- Staff actions ----------

create or replace function public.desk_mark(p_id text, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare me staff;
begin
  select * into me from staff where id = auth.uid() and active;
  if not found then raise exception 'forbidden'; end if;
  if p_status is not null and p_status not in ('checked-in', 'no-show') then raise exception 'bad_status'; end if;
  update bookings set
    desk_status = p_status,
    desk_by = case when p_status is null then null else me.username end,
    desk_by_name = case when p_status is null then null else me.name end,
    desk_at = case when p_status is null then null else now() end
  where id = p_id and status = 'booked';
end $$;

create or replace function public.mark_thread_seen(p_student uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then raise exception 'forbidden'; end if;
  update threads set staff_seen_at = now() where student = p_student;
end $$;

-- True while no active system admin exists (first-run setup).
create or replace function public.needs_bootstrap()
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from staff where role = 'admin' and active);
$$;

-- Keep the conversation list up to date.
create or replace function public._on_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare s students;
begin
  select * into s from students where id = new.student;
  insert into threads (student, sid, name, last_at, last_text, last_from, staff_seen_at)
  values (new.student, s.sid, s.name, new.at, left(new.text, 140), new.from_role,
          case when new.from_role = 'staff' then new.at else 'epoch'::timestamptz end)
  on conflict (student) do update set
    sid = excluded.sid, name = excluded.name, last_at = excluded.last_at,
    last_text = excluded.last_text, last_from = excluded.last_from,
    staff_seen_at = case when new.from_role = 'staff' then new.at else threads.staff_seen_at end;
  return new;
end $$;

drop trigger if exists messages_thread on public.messages;
create trigger messages_thread after insert on public.messages
  for each row execute function public._on_message();

-- ---------- Row-level security ----------

alter table public.config   enable row level security;
alter table public.staff    enable row level security;
alter table public.students enable row level security;
alter table public.bookings enable row level security;
alter table public.messages enable row level security;
alter table public.threads  enable row level security;

drop policy if exists config_read on public.config;
create policy config_read on public.config for select using (true);
drop policy if exists config_write on public.config;
create policy config_write on public.config for update using (public.is_admin()) with check (public.is_admin());

drop policy if exists staff_read on public.staff;
create policy staff_read on public.staff for select using (public.is_staff() or id = auth.uid());

drop policy if exists students_read on public.students;
create policy students_read on public.students for select using (id = auth.uid() or public.is_staff());
-- A student creates only their own row, with the student ID they signed up with.
drop policy if exists students_insert on public.students;
create policy students_insert on public.students for insert with check (
  id = auth.uid() and must_change = false
  and sid = split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1)
);

drop policy if exists bookings_read on public.bookings;
create policy bookings_read on public.bookings for select using (uid = auth.uid() or public.is_staff());

drop policy if exists messages_read on public.messages;
create policy messages_read on public.messages for select using (student = auth.uid() or public.is_staff());
drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages for insert with check (
  (from_role = 'student' and student = auth.uid() and read = true)
  or (from_role = 'staff' and public.is_staff())
);

drop policy if exists threads_read on public.threads;
create policy threads_read on public.threads for select using (public.is_staff());

-- ---------- Permissions ----------

revoke execute on function public._on_message() from public, anon, authenticated;
-- internal helpers are only called inside other functions
revoke execute on function public._check_slot(text, int, text) from public, anon, authenticated;
revoke execute on function public._taken(text, int, text, text) from public, anon, authenticated;
revoke execute on function public._rand4() from public, anon, authenticated;
-- signed-in actions: no access for visitors
revoke execute on function public.book(text, int, text) from public, anon;
revoke execute on function public.move_booking(text, int, text) from public, anon;
revoke execute on function public.cancel_booking(text) from public, anon;
revoke execute on function public.update_profile(text, text, text) from public, anon;
revoke execute on function public.clear_must_change() from public, anon;
revoke execute on function public.mark_read(bigint) from public, anon;
revoke execute on function public.desk_mark(text, text) from public, anon;
revoke execute on function public.mark_thread_seen(uuid) from public, anon;
grant execute on function public.availability(text) to anon, authenticated;
grant execute on function public.needs_bootstrap() to anon, authenticated;
grant execute on function public.book(text, int, text) to authenticated;
grant execute on function public.move_booking(text, int, text) to authenticated;
grant execute on function public.cancel_booking(text) to authenticated;
grant execute on function public.update_profile(text, text, text) to authenticated;
grant execute on function public.clear_must_change() to authenticated;
grant execute on function public.mark_read(bigint) to authenticated;
grant execute on function public.desk_mark(text, text) to authenticated;
grant execute on function public.mark_thread_seen(uuid) to authenticated;

-- ---------- Live updates ----------
do $$
begin
  begin alter publication supabase_realtime add table public.bookings; exception when others then null; end;
  begin alter publication supabase_realtime add table public.messages; exception when others then null; end;
  begin alter publication supabase_realtime add table public.threads;  exception when others then null; end;
  begin alter publication supabase_realtime add table public.config;   exception when others then null; end;
  begin alter publication supabase_realtime add table public.staff;    exception when others then null; end;
end $$;
