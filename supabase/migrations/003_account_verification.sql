-- ============================================================
-- Account verification: a supervisor checks a new student's details
-- against their university ID. Booking is not blocked meanwhile.
-- © 2026 Services Squire LLC. All rights reserved.
-- ============================================================

alter table public.students add column if not exists verified boolean not null default false;
alter table public.students add column if not exists verified_at timestamptz;
alter table public.students add column if not exists verified_by text not null default '';

-- Reception staff and system admins verify; only system admins can undo it.
create or replace function public.verify_student(p_student uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
declare me staff;
begin
  select * into me from staff where id = auth.uid() and active;
  if not found then raise exception 'forbidden'; end if;
  if not p_on and me.role <> 'admin' then raise exception 'forbidden'; end if;
  if not exists (select 1 from students where id = p_student) then raise exception 'not_found'; end if;
  if p_on then
    update students set verified = true, verified_at = now(), verified_by = me.name where id = p_student and not verified;
    if found then
      insert into messages (student, text, from_role, by_name, by_user)
      values (p_student, E'✅ تم التحقق من بيانات حسابك.\n✅ Your account details have been verified.', 'staff', me.name, me.username);
    end if;
  else
    update students set verified = false, verified_at = null, verified_by = '' where id = p_student;
  end if;
end $$;

-- A student who changes their name needs to be verified again.
create or replace function public.update_profile(p_name text, p_college text, p_phone text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if length(trim(p_name)) < 3 then raise exception 'bad_name'; end if;
  update students set
    verified = case when name is distinct from trim(p_name) then false else verified end,
    verified_at = case when name is distinct from trim(p_name) then null else verified_at end,
    verified_by = case when name is distinct from trim(p_name) then '' else verified_by end,
    name = trim(p_name), college = left(trim(coalesce(p_college, '')), 120),
    phone = left(trim(coalesce(p_phone, '')), 30)
  where id = auth.uid();
end $$;

revoke execute on function public.verify_student(uuid, boolean) from public, anon;
grant execute on function public.verify_student(uuid, boolean) to authenticated;
revoke execute on function public.update_profile(text, text, text) from public, anon;
grant execute on function public.update_profile(text, text, text) to authenticated;

-- New sign-ups always start unverified and unrestricted.
alter policy students_insert on public.students with check (
  id = auth.uid() and must_change = false and verified = false and restricted = false
  and sid = split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1)
);
