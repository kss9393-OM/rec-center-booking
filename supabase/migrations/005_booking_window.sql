-- ============================================================
-- Booking window: how many days ahead students may book (set by the system admin).
-- config.data.bookAhead = 0 (today only), 1 (through tomorrow), 2 (through the day after), … up to 30.
-- © 2026 Services Squire LLC. All rights reserved.
-- ============================================================

update public.config set data = data || jsonb_build_object('bookAhead', 6)
where id = 1 and not (data ? 'bookAhead');

create or replace function public._check_slot(p_date text, p_slot int, p_section text)
returns int language plpgsql stable security definer set search_path = public as $$
declare
  cfg jsonb; tz text; sl jsonb; cap int; ahead int;
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
  if ((p_date || ' ' || (sl ->> 's'))::timestamp at time zone tz) + interval '10 minutes' < now() then
    raise exception 'slot_closed';
  end if;
  ahead := greatest(0, least(30, coalesce((cfg ->> 'bookAhead')::int, 6)));
  if p_date::date > (now() at time zone tz)::date + ahead then raise exception 'too_far'; end if;
  return cap;
end $$;

revoke execute on function public._check_slot(text, int, text) from public, anon, authenticated;
