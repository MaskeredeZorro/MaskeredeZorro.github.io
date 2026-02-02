-- AKTIVER SIKKERHED PÅ ALLE TABELLER
alter table public.profiles enable row level security;
alter table public.rides enable row level security;
alter table public.bookings enable row level security;

-- REGLER FOR PROFILER
-- Alle kan se profiler (for at se hvem chaufføren er)
create policy "Public profiles are viewable by everyone" 
on public.profiles for select using (true);

-- Kun brugeren selv kan opdatere sin profil
create policy "Users can update own profile" 
on public.profiles for update using (auth.uid() = id);

-- REGLER FOR TURE (RIDES)
-- Alle kan se aktive ture (Søgning)
create policy "Rides are viewable by everyone" 
on public.rides for select using (true);

-- Kun verificerede brugere kan oprette ture (Her kræver vi login)
create policy "Authenticated users can create rides" 
on public.rides for insert with check (auth.role() = 'authenticated');

-- Kun chaufføren selv kan slette/aflyse sin tur
create policy "Drivers can update own rides" 
on public.rides for update using (auth.uid() = driver_id);

-- REGLER FOR BOOKINGS
-- Passagerer kan se deres egne bookings + Chaufføren kan se dem
create policy "Users can see own bookings and driver can see requests" 
on public.bookings for select 
using (auth.uid() = passenger_id or auth.uid() in (
    select driver_id from public.rides where id = ride_id
));