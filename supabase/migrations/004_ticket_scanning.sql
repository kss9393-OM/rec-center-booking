-- ============================================================
-- Ticket scanning at the desk (e.g. Honeywell EDA52 hardware scanner).
-- © 2026 Services Squire LLC. All rights reserved.
-- ============================================================

-- Ticket codes are unique within a day, so a scanned code never matches two bookings.
create or replace function public.book(p_date text, p_slot int, p_section text)
returns public.bookings language plpgsql security definer set search_path = public as $$
declare
  st students; cap int; v_id text; ex bookings; r bookings; v_code text; tries int := 0;
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
  loop
    v_code := 'CRC-' || substr(p_date, 1, 4) || '-' || _rand4();
    exit when not exists (select 1 from bookings where date = p_date and code = v_code and id <> v_id);
    tries := tries + 1;
    if tries > 20 then raise exception 'busy'; end if;
  end loop;
  insert into bookings (id, code, date, slot_id, section, student_id, student_name, uid, status)
  values (v_id, v_code, p_date, p_slot, p_section, st.sid, st.name, auth.uid(), 'booked')
  on conflict (id) do update set
    code = excluded.code, slot_id = excluded.slot_id, section = excluded.section,
    student_name = excluded.student_name, uid = excluded.uid, status = 'booked',
    desk_status = null, desk_by = null, desk_by_name = null, desk_at = null,
    created_at = now(), edited_at = null, cancelled_at = null
  returning * into r;
  return r;
end $$;

-- Scan a ticket: find it, check it, and check the student in, all in one step.
-- p_id   booking id from the QR code ('' when only a code was typed)
-- p_code ticket code (CRC-YYYY-XXXX)
-- p_date booking date from the QR code ('' = today)
-- p_force check in even when early / after the hour / after a no-show
create or replace function public.scan_ticket(p_id text, p_code text, p_date text, p_force boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me staff; b bookings; s students; cfg jsonb; tz text; today text; sl jsonb;
  now_local timestamp; t_start timestamp; t_end timestamp; n int; res text; info jsonb;
  early_min constant int := 15;
begin
  select * into me from staff where id = auth.uid() and active;
  if not found then raise exception 'forbidden'; end if;
  select data into cfg from config where id = 1;
  tz := coalesce(cfg ->> 'tz', 'Asia/Muscat');
  now_local := now() at time zone tz;
  today := to_char(now_local::date, 'YYYY-MM-DD');

  if coalesce(p_id, '') <> '' then
    select * into b from bookings where id = p_id and upper(code) = upper(coalesce(p_code, ''));
  end if;
  if b.id is null and coalesce(p_code, '') <> '' then
    select count(*) into n from bookings where upper(code) = upper(p_code) and date = coalesce(nullif(p_date, ''), today);
    if n > 1 then return jsonb_build_object('result', 'ambiguous'); end if;
    select * into b from bookings where upper(code) = upper(p_code) and date = coalesce(nullif(p_date, ''), today);
  end if;
  if b.id is null then return jsonb_build_object('result', 'not_found'); end if;

  select * into s from students where id = b.uid;
  select x into sl from jsonb_array_elements(coalesce(cfg -> 'slots', '[]')) x where (x ->> 'id')::int = b.slot_id;
  if sl is not null then
    t_start := (b.date || ' ' || (sl ->> 's'))::timestamp;
    t_end   := (b.date || ' ' || (sl ->> 'e'))::timestamp;
  end if;

  if b.status = 'cancelled' then res := 'cancelled';
  elsif b.desk_status = 'checked-in' then res := 'already';
  elsif b.date <> today then res := case when b.date < today then 'past_day' else 'future_day' end;
  elsif t_start is not null and now_local < t_start - make_interval(mins => early_min) and not p_force then res := 'early';
  elsif t_end is not null and now_local > t_end and not p_force then res := 'ended';
  elsif b.desk_status = 'no-show' and not p_force then res := 'was_no_show';
  else
    update bookings set desk_status = 'checked-in', desk_by = me.username, desk_by_name = me.name, desk_at = now()
    where id = b.id returning * into b;
    res := 'ok';
  end if;

  info := jsonb_build_object(
    'result', res, 'id', b.id, 'code', b.code, 'date', b.date, 'slot_id', b.slot_id, 'section', b.section,
    'student_id', b.student_id, 'student_name', coalesce(s.name, b.student_name), 'uid', b.uid,
    'desk_status', b.desk_status, 'desk_by_name', b.desk_by_name, 'desk_at', b.desk_at,
    'verified', coalesce(s.verified, false), 'restricted', coalesce(_is_restricted(b.uid), false),
    'late', (t_start is not null and now_local > t_start + interval '10 minutes'));
  return info;
end $$;

revoke execute on function public.scan_ticket(text, text, text, boolean) from public, anon;
grant execute on function public.scan_ticket(text, text, text, boolean) to authenticated;
revoke execute on function public.book(text, int, text) from public, anon;
grant execute on function public.book(text, int, text) to authenticated;
