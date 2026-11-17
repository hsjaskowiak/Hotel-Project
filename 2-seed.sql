-- STEP 2: First create your own login in Supabase > Authentication > Users
-- (Add user > Create new user, with email + password, "Auto confirm user" on).
-- Then replace YOUR_EMAIL_HERE below with that email and run this file.

do $$
declare
  h uuid;
  u uuid;
begin
  select id into u from auth.users where email = 'YOUR_EMAIL_HERE';
  if u is null then
    raise exception 'No user with that email. Create it under Authentication > Users first.';
  end if;

  insert into hotels (name) values ('Harbor Lane Hotel') returning id into h;
  insert into profiles (id, hotel_id, name, role) values (u, h, 'Manager', 'manager');

  insert into rooms (hotel_id, number, floor, type)
  select h, (f * 100 + i)::text, f,
         case when i in (5, 10) then 'Suite'
              when i in (4, 9) then 'Double queen'
              else 'King' end
  from generate_series(1, 4) f, generate_series(1, 10) i;
end $$;
