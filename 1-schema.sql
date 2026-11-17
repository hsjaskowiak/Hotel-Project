-- STEP 1: Run this whole file once in Supabase > SQL Editor.

-- Tables ---------------------------------------------------------------
create table hotels (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  hotel_id uuid not null references hotels on delete cascade,
  name text not null,
  role text not null check (role in ('manager', 'front_desk', 'housekeeping'))
);

create table rooms (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references hotels on delete cascade,
  number text not null,
  floor int not null,
  type text not null,
  status text not null default 'vacant'
    check (status in ('vacant', 'occupied', 'dirty', 'cleaning', 'ooo')),
  guest text not null default '',
  check_in date,
  check_out date,
  note text not null default '',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users,
  unique (hotel_id, number)
);

-- Activity log + messages between front desk and housekeeping
create table room_events (
  id bigint generated always as identity primary key,
  hotel_id uuid not null references hotels on delete cascade,
  room_id uuid not null references rooms on delete cascade,
  user_id uuid references auth.users,
  kind text not null check (kind in ('status', 'message')),
  message text not null,
  created_at timestamptz not null default now()
);

create index on rooms (hotel_id, floor);
create index on room_events (hotel_id, created_at desc);

-- Security: each person only sees their own hotel's data ------------------
create function public.my_hotel_id() returns uuid
language sql stable security definer set search_path = public as $$
  select hotel_id from profiles where id = auth.uid()
$$;

alter table hotels enable row level security;
alter table profiles enable row level security;
alter table rooms enable row level security;
alter table room_events enable row level security;

create policy "see own hotel" on hotels for select using (id = my_hotel_id());
create policy "see own hotel staff" on profiles for select
  using (hotel_id = my_hotel_id());
create policy "see own hotel rooms" on rooms for select
  using (hotel_id = my_hotel_id());
create policy "update own hotel rooms" on rooms for update
  using (hotel_id = my_hotel_id()) with check (hotel_id = my_hotel_id());
create policy "see own hotel events" on room_events for select
  using (hotel_id = my_hotel_id());
create policy "add own hotel events" on room_events for insert
  with check (hotel_id = my_hotel_id() and user_id = auth.uid());

-- Automatically record who changed a room's status, and when -------------
create function public.log_room_change() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  new.updated_by = auth.uid();
  if new.status is distinct from old.status then
    insert into room_events (hotel_id, room_id, user_id, kind, message)
    values (new.hotel_id, new.id, auth.uid(), 'status', old.status || ' -> ' || new.status);
  end if;
  return new;
end $$;

create trigger rooms_log before update on rooms
  for each row execute function log_room_change();

-- Live updates: screens listen for changes to these tables ---------------
alter publication supabase_realtime add table rooms, room_events;
