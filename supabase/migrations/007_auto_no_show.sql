-- ============================================================
-- Automatic no-show cancellation, automatic warnings for repeat no-shows,
-- and alerts for supervisors.
-- © 2026 Services Squire LLC. All rights reserved.
--
-- config.data.autoNoShow = {"on":true,"minutes":10,"warnAfter":2,"windowDays":30}
--   minutes    : cancel when not checked in this long after the hour starts
--   warnAfter  : automatic warning after this many no-shows (0 = never)
--   windowDays : counted within this many days
-- The job runs every minute (see 008_auto_no_show_schedule.sql).
-- ============================================================

update public.config
set data = data || jsonb_build_object('autoNoShow', jsonb_build_object('on', true, 'minutes', 10, 'warnAfter', 2, 'windowDays', 30))
where id = 1 and not (data ? 'autoNoShow');

alter table public.warnings add column if not exists auto boolean not null default false;

-- Alerts for supervisors (reception staff and system admins).
create table if not exists public.alerts (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('no_show', 'auto_warning')),
  student uuid references auth.users (id) on delete cascade,
  booking_id text,
  text text not null,
  at timestamptz not null default now(),
  read_at timestamptz,
  read_by text not null default ''
);
create index if not exists alerts_at_idx on public.alerts (at desc);
alter table public.alerts enable row level security;
drop policy if exists alerts_read on public.alerts;
create policy alerts_read on public.alerts for select using (public.is_staff());

create or replace function public.mark_alerts_read(p_ids bigint[])
returns void language plpgsql security definer set search_path = public as $$
declare me staff;
begin
  select * into me from staff where id = auth.uid() and active;
  if not found then raise exception 'forbidden'; end if;
  update alerts set read_at = now(), read_by = me.name
  where read_at is null and (p_ids is null or id = any (p_ids));
end $$;

-- Issue an automatic warning when a student reaches the no-show threshold
-- (counting no-shows since their last automatic warning, within the window).
create or replace function public._maybe_auto_warn(p_student uuid, p_booking text)
returns void language plpgsql security definer set search_path = public as $$
declare cfg jsonb; warn_after int; win int; last_auto timestamptz; cnt int; total int; st students;
begin
  select data into cfg from config where id = 1;
  warn_after := greatest(0, least(20, coalesce((cfg -> 'autoNoShow' ->> 'warnAfter')::int, 2)));
  if warn_after = 0 then return; end if;
  win := greatest(1, least(365, coalesce((cfg -> 'autoNoShow' ->> 'windowDays')::int, 30)));
  select max(at) into last_auto from warnings where student = p_student and auto and deleted_at is null;
  select count(*) into cnt from bookings
  where uid = p_student and status = 'booked' and desk_status = 'no-show'
    and desk_at > greatest(now() - make_interval(days => win), coalesce(last_auto, 'epoch'::timestamptz));
  if cnt < warn_after then return; end if;
  select * into st from students where id = p_student;
  insert into warnings (student, reason, by_name, auto)
  values (p_student, 'تكرار عدم الحضور (' || cnt || ' مرات خلال ' || win || ' يوماً)', 'النظام (تلقائي)', true);
  select count(*) into total from warnings where student = p_student and deleted_at is null;
  insert into messages (student, text, from_role, by_name, by_user)
  values (p_student, '⚠️ إنذار رسمي رقم ' || total || ': تكرار عدم الحضور (' || cnt || ' مرات خلال ' || win || ' يوماً).'
          || E'\n⚠️ Formal warning #' || total || ': repeated no-shows.', 'staff', 'النظام (تلقائي)', 'system');
  insert into alerts (kind, student, booking_id, text)
  values ('auto_warning', p_student, p_booking,
          coalesce(st.name, '') || ' (' || coalesce(st.sid, '') || ') حصل على إنذار تلقائي رقم ' || total
          || ' لتكرار عدم الحضور (' || cnt || ' مرات خلال ' || win || ' يوماً).');
end $$;

-- Runs every minute: cancel bookings with no check-in N minutes after the hour starts.
create or replace function public.auto_no_show()
returns int language plpgsql security definer set search_path = public as $$
declare
  cfg jsonb; tz text; mins int; now_local timestamp; today text; r record; n int := 0; sec_name text;
begin
  select data into cfg from config where id = 1;
  if not coalesce((cfg -> 'autoNoShow' ->> 'on')::boolean, true) then return 0; end if;
  mins := greatest(1, least(120, coalesce((cfg -> 'autoNoShow' ->> 'minutes')::int, 10)));
  tz := coalesce(cfg ->> 'tz', 'Asia/Muscat');
  now_local := now() at time zone tz;
  today := to_char(now_local::date, 'YYYY-MM-DD');
  for r in
    select b.id, b.uid, b.section, b.student_id, b.student_name, sl.s ->> 's' as s_start
    from bookings b
    join lateral (select x as s from jsonb_array_elements(coalesce(cfg -> 'slots', '[]')) x
                  where (x ->> 'id')::int = b.slot_id) sl on true
    where b.date = today and b.status = 'booked' and b.desk_status is null
      and (b.date || ' ' || (sl.s ->> 's'))::timestamp + make_interval(mins => mins) <= now_local
    for update of b skip locked
  loop
    update bookings set desk_status = 'no-show', desk_by = 'system', desk_by_name = 'النظام (تلقائي)', desk_at = now()
    where id = r.id;
    n := n + 1;
    select x ->> 'ar' into sec_name from jsonb_array_elements(coalesce(cfg -> 'sections', '[]')) x where x ->> 'id' = r.section;
    insert into messages (student, text, from_role, by_name, by_user)
    values (r.uid, 'تم إلغاء حجزك تلقائياً لعدم الحضور خلال ' || mins || ' دقائق من بداية الساعة (' || coalesce(sec_name, r.section) || ' — ' || r.s_start || ').'
            || E'\nYour booking was cancelled automatically: no check-in within ' || mins || ' minutes of the start.',
            'staff', 'النظام (تلقائي)', 'system');
    insert into alerts (kind, student, booking_id, text)
    values ('no_show', r.uid, r.id,
            r.student_name || ' (' || r.student_id || ') لم يحضر خلال ' || mins || ' دقائق — '
            || coalesce(sec_name, r.section) || ' ' || r.s_start || '. أُلغي الحجز تلقائياً وحُرّر المقعد.');
    perform _maybe_auto_warn(r.uid, r.id);
  end loop;
  return n;
end $$;

-- A no-show marked by hand at the desk also counts toward the automatic warning.
create or replace function public.desk_mark(p_id text, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare me staff; b bookings;
begin
  select * into me from staff where id = auth.uid() and active;
  if not found then raise exception 'forbidden'; end if;
  if p_status is not null and p_status not in ('checked-in', 'no-show') then raise exception 'bad_status'; end if;
  update bookings set
    desk_status = p_status,
    desk_by = case when p_status is null then null else me.username end,
    desk_by_name = case when p_status is null then null else me.name end,
    desk_at = case when p_status is null then null else now() end
  where id = p_id and status = 'booked'
  returning * into b;
  if p_status = 'no-show' and b.id is not null then perform _maybe_auto_warn(b.uid, b.id); end if;
end $$;

revoke execute on function public.auto_no_show() from public, anon, authenticated;
revoke execute on function public._maybe_auto_warn(uuid, text) from public, anon, authenticated;
revoke execute on function public.mark_alerts_read(bigint[]) from public, anon;
grant execute on function public.mark_alerts_read(bigint[]) to authenticated;
revoke execute on function public.desk_mark(text, text) from public, anon;
grant execute on function public.desk_mark(text, text) to authenticated;

do $$ begin
  begin alter publication supabase_realtime add table public.alerts; exception when others then null; end;
end $$;
