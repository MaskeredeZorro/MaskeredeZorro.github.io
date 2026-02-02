-- 1. AKTIVERING AF GPS-MOTOR (KRITISK FOR SØGNING)
-- Uden denne extension kan vi ikke lave "Find ture i nærheden af mig"
create extension if not exists postgis schema extensions;

-- 2. OPRETTELSE AF PROFILER (KOBLET TIL LOGIN)
-- Denne tabel synkroniseres automatisk med Supabase Auth
create table public.profiles (
  id uuid references auth.users not null primary key,
  full_name text,
  avatar_url text,
  phone_number text,
  is_verified_mitid boolean default false, -- Viser det grønne skjold
  is_verified_driver boolean default false, -- Har kørekort/bil tjek
  stripe_customer_id text, -- Til betaling
  created_at timestamptz default now()
);

-- 3. OPRETTELSE AF TURE (RIDES)
-- Her bruger vi 'geography' typen til at gemme præcise koordinater
create table public.rides (
  id uuid default uuid_generate_v4() primary key,
  driver_id uuid references public.profiles(id) not null,
  
  -- Rute Info
  origin_city text not null,
  destination_city text not null,
  
  -- GPS Koordinater (PostGIS Geography)
  -- Point(Lengdegrad, Breddegrad)
  origin_location geography(Point) not null, 
  destination_location geography(Point) not null,
  
  -- Tidsplan & Økonomi
  departure_time timestamptz not null,
  price_dkk integer not null, -- Gemmes altid i øre eller hele kr. (undgå decimalfejl)
  seats_available integer default 3,
  
  -- Bil & Beskrivelse
  car_model text, -- Fx "Tesla Model 3"
  description text,
  
  -- Status
  status text default 'active' check (status in ('active', 'full', 'cancelled', 'completed')),
  
  created_at timestamptz default now()
);

-- 4. OPRETTELSE AF TURALARMER (ALERTS)
-- Bruges til at sende push-beskeder, når nye ture matcher
create table public.ride_alerts (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references public.profiles(id),
  
  origin_city text,
  destination_city text,
  
  -- Gemmer enhedens ID til Firebase Cloud Messaging
  fcm_token text not null, 
  
  created_at timestamptz default now()
);

-- 5. BOOKINGS (Fase 3 forberedelse, men vi laver tabellen nu for at undgå fejl)
create table public.bookings (
  id uuid default uuid_generate_v4() primary key,
  ride_id uuid references public.rides(id) not null,
  passenger_id uuid references public.profiles(id) not null,
  seats_booked integer default 1,
  status text default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  created_at timestamptz default now()
);