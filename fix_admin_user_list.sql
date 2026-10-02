-- Fix owner/admin user list for YKKHOJA
-- Run this whole script once in Supabase > SQL Editor.

-- 1) Make sure profiles has a phone field.
alter table public.profiles
add column if not exists phone text;

-- 2) Sync any existing Authentication users into profiles.
insert into public.profiles (id, full_name, username, phone, email, role, created_at)
select
  u.id,
  coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', ''),
  nullif(u.raw_user_meta_data->>'username', ''),
  nullif(u.raw_user_meta_data->>'phone', ''),
  u.email,
  case when u.email = 'nouramr787898@gmail.com' then 'admin' else 'user' end,
  u.created_at
from auth.users u
on conflict (id) do update set
  full_name = excluded.full_name,
  username = coalesce(excluded.username, public.profiles.username),
  phone = coalesce(excluded.phone, public.profiles.phone),
  email = excluded.email,
  role = case
    when excluded.email = 'nouramr787898@gmail.com' then 'admin'
    else public.profiles.role
  end;

-- 3) Keep future signups synchronized automatically.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, username, phone, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''),
    nullif(new.raw_user_meta_data->>'username', ''),
    nullif(new.raw_user_meta_data->>'phone', ''),
    new.email
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    username = coalesce(excluded.username, public.profiles.username),
    phone = coalesce(excluded.phone, public.profiles.phone),
    email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert or update of email, raw_user_meta_data on auth.users
for each row execute procedure public.handle_new_user();

-- 4) Secure RPC: only an admin can retrieve the complete user list.
create or replace function public.admin_list_users()
returns table (
  full_name text,
  username text,
  phone text,
  email text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  ) then
    raise exception 'Not authorized';
  end if;

  return query
  select p.full_name, p.username, p.phone, p.email, p.created_at
  from public.profiles p
  order by p.created_at desc;
end;
$$;

revoke all on function public.admin_list_users() from public;
grant execute on function public.admin_list_users() to authenticated;

-- 5) Verification result: this should show all synced profiles.
select email, username, phone, role, created_at
from public.profiles
order by created_at desc;
