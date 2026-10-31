-- ============================================================
-- Closures with reasons (hours/shift on a date, a zone for a period)
-- and deleting a warning with a reason (kept for the record).
-- © 2026 Services Squire LLC. All rights reserved.
--
-- config.data additions:
--   weeklyOffReasons: {"5": "عطلة نهاية الأسبوع", ...}            (display only)
--   closedSlots:      [{"date":"2026-11-03","slots":[5,6,7,8],"reason":"..."}]
--   zoneClosures:     [{"section":"billiards","from":"2026-11-01","to":"","reason":"..."}]  (to "" = until reopened)
-- ============================================================

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
  if exists (select 1 from jsonb_array_elements(coalesce(cfg -> 'closedSlots', '[]')) c
             where c ->> 'date' = p_date and coalesce(c -> 'slots', '[]') @> to_jsonb(p_slot)) then
    raise exception 'closed_slot';
  end if;
  if exists (select 1 from jsonb_array_elements(coalesce(cfg -> 'zoneClosures', '[]')) z
             where z ->> 'section' = p_section
               and coalesce(z ->> 'from', '') <= p_date
               and (coalesce(z ->> 'to', '') = '' or z ->> 'to' >= p_date)) then
    raise exception 'closed_zone';
  end if;
  if ((p_date || ' ' || (sl ->> 's'))::timestamp at time zone tz) + interval '10 minutes' < now() then
    raise exception 'slot_closed';
  end if;
  ahead := greatest(0, least(30, coalesce((cfg ->> 'bookAhead')::int, 6)));
  if p_date::date > (now() at time zone tz)::date + ahead then raise exception 'too_far'; end if;
  return cap;
end $$;
revoke execute on function public._check_slot(text, int, text) from public, anon, authenticated;

-- Warnings: deleting keeps the row (with reason, who, when) for the record; the student stops seeing it.
alter table public.warnings add column if not exists deleted_at timestamptz;
alter table public.warnings add column if not exists deleted_by text not null default '';
alter table public.warnings add column if not exists delete_reason text not null default '';

drop policy if exists warnings_read on public.warnings;
create policy warnings_read on public.warnings for select
  using ((student = auth.uid() and deleted_at is null) or public.is_staff());

-- Numbering counts only warnings that are still in force.
create or replace function public.admin_warn(p_student uuid, p_reason text)
returns int language plpgsql security definer set search_path = public as $$
declare me staff; total int;
begin
  select * into me from staff where id = auth.uid() and active and role = 'admin';
  if not found then raise exception 'forbidden'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'bad_reason'; end if;
  if not exists (select 1 from students where id = p_student) then raise exception 'not_found'; end if;
  insert into warnings (student, reason, by_name) values (p_student, left(trim(p_reason), 500), me.name);
  select count(*) into total from warnings where student = p_student and deleted_at is null;
  insert into messages (student, text, from_role, by_name, by_user)
  values (p_student, '⚠️ إنذار رسمي رقم ' || total || ': ' || trim(p_reason) || E'\n⚠️ Formal warning #' || total || '.', 'staff', me.name, me.username);
  return total;
end $$;

drop function if exists public.admin_delete_warning(bigint);
create or replace function public.admin_delete_warning(p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare me staff; w warnings;
begin
  select * into me from staff where id = auth.uid() and active and role = 'admin';
  if not found then raise exception 'forbidden'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'bad_reason'; end if;
  update warnings set deleted_at = now(), deleted_by = me.name, delete_reason = left(trim(p_reason), 500)
  where id = p_id and deleted_at is null returning * into w;
  if w.id is null then raise exception 'not_found'; end if;
  insert into messages (student, text, from_role, by_name, by_user)
  values (w.student, '✅ تم إلغاء إنذار: ' || w.reason || E'\nسبب الإلغاء: ' || trim(p_reason) || E'\n✅ A warning was withdrawn.', 'staff', me.name, me.username);
end $$;

revoke execute on function public.admin_delete_warning(bigint, text) from public, anon;
grant execute on function public.admin_delete_warning(bigint, text) to authenticated;
revoke execute on function public.admin_warn(uuid, text) from public, anon;
grant execute on function public.admin_warn(uuid, text) to authenticated;
