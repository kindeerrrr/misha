-- =============================================================================
-- misha — полная схема БД (Phase 0–4)
-- Выполни в Supabase SQL Editor
-- =============================================================================

-- Extensions
create extension if not exists "uuid-ossp";

-- =============================================================================
-- PROFILES
-- =============================================================================
create table if not exists profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text not null,
  created_at  timestamptz default now()
);

-- Auto-create profile on signup
create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- =============================================================================
-- MEDICATIONS (Phase 1)
-- =============================================================================
create table if not exists medications (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  name         text not null,
  frequency    text not null default 'daily',    -- daily|twice_daily|weekdays|weekly|custom
  time_of_day  text,                              -- morning|afternoon|evening|with_food|HH:MM
  criticality  text not null default 'medium',   -- high|medium|low
  status       text not null default 'active',   -- active|paused|planned
  notes        text,
  created_at   timestamptz default now()
);

create table if not exists medication_logs (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  medication_id   uuid not null references medications(id) on delete cascade,
  taken_at        timestamptz not null default now(),
  skipped         boolean not null default false,
  skip_reason     text,
  date            date not null,
  created_at      timestamptz default now()
);

create index if not exists idx_med_logs_user_date on medication_logs(user_id, date);

-- =============================================================================
-- SLEEP (Phase 1)
-- =============================================================================
create table if not exists sleep_logs (
  id                uuid primary key default uuid_generate_v4(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  date              date not null,
  bedtime           timestamptz,
  wake_time         timestamptz,
  duration_minutes  int,
  quality           smallint check (quality between 1 and 5),
  notes             text,
  created_at        timestamptz default now(),
  unique (user_id, date)
);

-- =============================================================================
-- MEASUREMENTS (Phase 1)
-- =============================================================================
create table if not exists daily_weights (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  date        date not null,
  weight_kg   numeric(5,2) not null,
  created_at  timestamptz default now(),
  unique (user_id, date)
);

create table if not exists weekly_measurements (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  date        date not null,
  weight_kg   numeric(5,2),
  water_pct   numeric(5,2),
  muscle_pct  numeric(5,2),
  fat_pct     numeric(5,2),
  bone_kg     numeric(5,2),
  chest_cm    numeric(5,1),
  waist_cm    numeric(5,1),
  hips_cm     numeric(5,1),
  created_at  timestamptz default now(),
  unique (user_id, date)
);

-- =============================================================================
-- WORKOUTS (Phase 1)
-- =============================================================================
create table if not exists workout_types (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  icon        text,
  is_default  boolean not null default false,
  created_at  timestamptz default now()
);

create table if not exists workout_logs (
  id                uuid primary key default uuid_generate_v4(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  workout_type_id   uuid not null references workout_types(id) on delete cascade,
  date              date not null,
  duration_minutes  int not null,
  intensity         smallint check (intensity between 1 and 5),
  notes             text,
  created_at        timestamptz default now()
);

create index if not exists idx_workout_logs_user_date on workout_logs(user_id, date);

-- =============================================================================
-- DOCTORS & RESEARCH (Phase 1)
-- =============================================================================
create table if not exists doctor_visits (
  id               uuid primary key default uuid_generate_v4(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  date             date not null,
  doctor_category  text not null,
  procedure        text not null,
  notes            text,
  file_urls        text[] not null default '{}',
  created_at       timestamptz default now()
);

create index if not exists idx_doctor_visits_user on doctor_visits(user_id, date desc);

create table if not exists medical_research (
  id             uuid primary key default uuid_generate_v4(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  date           date not null,
  research_type  text not null,       -- УЗИ|МРТ|КТ|ЭКГ|Эндоскопия|Биопсия|Рентген|Другое
  body_part      text,
  description    text,
  file_urls      text[] not null default '{}',
  created_at     timestamptz default now()
);

-- =============================================================================
-- ANNUAL CHECKUPS (Phase 1)
-- =============================================================================
create table if not exists annual_checkups (
  id                uuid primary key default uuid_generate_v4(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  name              text not null,
  frequency_months  int not null default 12,
  last_done_at      date,
  next_due_at       date,
  reminder_2w       boolean not null default true,
  reminder_3d       boolean not null default true,
  notes             text,
  created_at        timestamptz default now()
);

-- =============================================================================
-- EMOTIONS & DAY REPORTS (Phase 1)
-- =============================================================================
create table if not exists emotion_entries (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  emoji        text not null,
  note         text,
  date         date not null,
  recorded_at  timestamptz not null default now(),
  created_at   timestamptz default now()
);

create index if not exists idx_emotion_entries_user_date on emotion_entries(user_id, date desc);

create table if not exists day_reports (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  date          date not null,
  overall       smallint check (overall between 1 and 5),
  energy        smallint check (energy between 1 and 5),
  anxiety       smallint check (anxiety between 1 and 5),
  productivity  smallint check (productivity between 1 and 5),
  warmth        smallint check (warmth between 1 and 5),
  highlight     text,
  low_point     text,
  gratitude     text,
  created_at    timestamptz default now(),
  unique (user_id, date)
);

-- =============================================================================
-- FINANCES (Phase 1)
-- =============================================================================
create table if not exists expense_categories (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  emoji       text not null default '◎',
  group_name  text not null default 'Прочее',
  is_quick    boolean not null default false,
  sort_order  int not null default 100,
  created_at  timestamptz default now()
);

create table if not exists expenses (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  date         date not null,
  amount       numeric(10,2) not null,
  category_id  uuid not null references expense_categories(id) on delete restrict,
  note         text,
  created_at   timestamptz default now()
);

create index if not exists idx_expenses_user_date on expenses(user_id, date desc);

-- =============================================================================
-- FOOD LOGS (Phase 2)
-- =============================================================================
create table if not exists food_logs (
  id               uuid primary key default uuid_generate_v4(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  date             date not null,
  meal_time        text,               -- breakfast|lunch|dinner|snack
  raw_text         text,               -- original voice/text input
  items            jsonb,              -- parsed items [{name, grams, kcal, protein, fat, carbs}]
  total_kcal       int,
  photo_url        text,
  created_at       timestamptz default now()
);

-- =============================================================================
-- CREDITS (Phase 2)
-- =============================================================================
create table if not exists credits (
  id                uuid primary key default uuid_generate_v4(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  name              text not null,
  lender            text,
  principal         numeric(12,2),
  balance           numeric(12,2),
  is_complex        boolean not null default false,  -- toggle "Сложный долг"
  monthly_day       smallint,          -- day of month for simple mode
  monthly_amount    numeric(10,2),
  start_date        date,
  end_date          date,
  notes             text,
  is_active         boolean not null default true,
  created_at        timestamptz default now()
);

create table if not exists credit_payments (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  credit_id   uuid not null references credits(id) on delete cascade,
  due_date    date not null,
  paid_date   date,
  amount      numeric(10,2) not null,
  is_paid     boolean not null default false,
  created_at  timestamptz default now()
);

-- =============================================================================
-- MEDIA: BOOKS / MOVIES / SERIES (Phase 2)
-- =============================================================================
create table if not exists media_items (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  type        text not null,           -- book|movie|series
  title       text not null,
  creator     text,                    -- author / director
  genres      text[],
  status      text not null default 'want',  -- want|in_progress|archive
  rating      smallint check (rating between 1 and 5),
  notes       text,
  cover_url   text,
  total_pages int,                     -- books
  current_page int,                    -- books
  created_at  timestamptz default now()
);

create table if not exists reading_sessions (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  media_id      uuid not null references media_items(id) on delete cascade,
  date          date not null,
  started_at    timestamptz,
  ended_at      timestamptz,
  duration_min  int,
  pages_read    int,
  created_at    timestamptz default now()
);

-- =============================================================================
-- HABITS (Phase 2)
-- =============================================================================
create table if not exists habits (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  emoji       text,
  frequency   text not null default 'daily',
  is_active   boolean not null default true,
  created_at  timestamptz default now()
);

create table if not exists habit_logs (
  id        uuid primary key default uuid_generate_v4(),
  user_id   uuid not null references auth.users(id) on delete cascade,
  habit_id  uuid not null references habits(id) on delete cascade,
  date      date not null,
  done      boolean not null default true,
  created_at timestamptz default now(),
  unique (habit_id, date)
);

-- =============================================================================
-- CAT (Phase 2)
-- =============================================================================
create table if not exists cat_profile (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  breed       text,
  birth_date  date,
  photo_url   text,
  notes       text,
  created_at  timestamptz default now()
);

create table if not exists cat_vaccines (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  cat_id        uuid not null references cat_profile(id) on delete cascade,
  name          text not null,
  given_at      date,
  next_due_at   date,
  notes         text,
  created_at    timestamptz default now()
);

create table if not exists cat_health_events (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  cat_id      uuid not null references cat_profile(id) on delete cascade,
  date        date not null,
  type        text,                 -- vomit|vet|behaviour|weight|other
  description text,
  file_urls   text[] default '{}',
  created_at  timestamptz default now()
);

create table if not exists cat_grooming (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  cat_id        uuid not null references cat_profile(id) on delete cascade,
  date          date not null,
  next_due_at   date,
  notes         text,
  created_at    timestamptz default now()
);

create table if not exists cat_food_orders (
  id               uuid primary key default uuid_generate_v4(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  cat_id           uuid not null references cat_profile(id) on delete cascade,
  ordered_at       date not null,
  brand            text,
  product_name     text,
  quantity         text,
  next_order_est   date,
  notes            text,
  created_at       timestamptz default now()
);

-- =============================================================================
-- TRAVELS (Phase 3)
-- =============================================================================
create table if not exists travels (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  country     text,
  city        text,
  start_date  date,
  end_date    date,
  notes       text,
  cover_url   text,
  is_active   boolean not null default true,
  created_at  timestamptz default now()
);

create table if not exists travel_places (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  travel_id    uuid not null references travels(id) on delete cascade,
  name         text not null,
  category     text,               -- food|city|shop|museum|nature|other
  address      text,
  lat          numeric(10,7),
  lng          numeric(10,7),
  notes        text,
  visited      boolean not null default false,
  created_at   timestamptz default now()
);

create table if not exists travel_luggage (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  travel_id    uuid not null references travels(id) on delete cascade,
  container    text not null default 'Чемодан',
  weight_kg    numeric(5,2),
  items        jsonb,              -- [{name, packed, category}]
  created_at   timestamptz default now()
);

create table if not exists travel_documents (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  travel_id    uuid not null references travels(id) on delete cascade,
  name         text not null,
  doc_type     text,               -- passport|ticket|booking|visa|other
  file_url     text,
  notes        text,
  created_at   timestamptz default now()
);

-- =============================================================================
-- NOTION SYNC LOG (stub)
-- =============================================================================
create table if not exists notion_sync_log (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  table_name   text not null,
  record_id    uuid not null,
  synced_at    timestamptz not null default now(),
  status       text not null default 'pending'  -- pending|done|error
);

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

-- Enable RLS on all tables
alter table profiles                enable row level security;
alter table medications              enable row level security;
alter table medication_logs          enable row level security;
alter table sleep_logs               enable row level security;
alter table daily_weights            enable row level security;
alter table weekly_measurements      enable row level security;
alter table workout_types            enable row level security;
alter table workout_logs             enable row level security;
alter table doctor_visits            enable row level security;
alter table medical_research         enable row level security;
alter table annual_checkups          enable row level security;
alter table emotion_entries          enable row level security;
alter table day_reports              enable row level security;
alter table expense_categories       enable row level security;
alter table expenses                 enable row level security;
alter table food_logs                enable row level security;
alter table credits                  enable row level security;
alter table credit_payments          enable row level security;
alter table media_items              enable row level security;
alter table reading_sessions         enable row level security;
alter table habits                   enable row level security;
alter table habit_logs               enable row level security;
alter table cat_profile              enable row level security;
alter table cat_vaccines             enable row level security;
alter table cat_health_events        enable row level security;
alter table cat_grooming             enable row level security;
alter table cat_food_orders          enable row level security;
alter table travels                  enable row level security;
alter table travel_places            enable row level security;
alter table travel_luggage           enable row level security;
alter table travel_documents         enable row level security;
alter table notion_sync_log          enable row level security;

-- Helper macro: every table with user_id gets the same 4 policies
-- (select / insert / update / delete own rows only)

-- profiles uses id (not user_id) as the owner column
drop policy if exists "profiles_select_own" on profiles;
create policy "profiles_select_own" on profiles for select using (auth.uid() = id);

drop policy if exists "profiles_insert_own" on profiles;
create policy "profiles_insert_own" on profiles for insert with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on profiles;
create policy "profiles_update_own" on profiles for update using (auth.uid() = id);

drop policy if exists "profiles_delete_own" on profiles;
create policy "profiles_delete_own" on profiles for delete using (auth.uid() = id);

-- All other tables use user_id
do $$
declare
  t text;
  tables text[] := array[
    'medications','medication_logs','sleep_logs',
    'daily_weights','weekly_measurements','workout_types','workout_logs',
    'doctor_visits','medical_research','annual_checkups',
    'emotion_entries','day_reports','expense_categories','expenses',
    'food_logs','credits','credit_payments','media_items','reading_sessions',
    'habits','habit_logs','cat_profile','cat_vaccines','cat_health_events',
    'cat_grooming','cat_food_orders',
    'travels','travel_places','travel_luggage','travel_documents',
    'notion_sync_log'
  ];
begin
  foreach t in array tables loop
    execute format('
      drop policy if exists "%1$s_select_own" on %1$s;
      create policy "%1$s_select_own" on %1$s for select using (auth.uid() = user_id);

      drop policy if exists "%1$s_insert_own" on %1$s;
      create policy "%1$s_insert_own" on %1$s for insert with check (auth.uid() = user_id);

      drop policy if exists "%1$s_update_own" on %1$s;
      create policy "%1$s_update_own" on %1$s for update using (auth.uid() = user_id);

      drop policy if exists "%1$s_delete_own" on %1$s;
      create policy "%1$s_delete_own" on %1$s for delete using (auth.uid() = user_id);
    ', t);
  end loop;
end;
$$;

-- =============================================================================
-- STORAGE BUCKETS
-- =============================================================================
-- Run these in Supabase Storage section OR via SQL:

insert into storage.buckets (id, name, public)
values ('medical-files', 'medical-files', true)
on conflict (id) do nothing;

-- Storage policies: owner can read/write own files
create policy "medical-files owner access"
  on storage.objects for all
  using (bucket_id = 'medical-files' and auth.uid()::text = (storage.foldername(name))[1])
  with check (bucket_id = 'medical-files' and auth.uid()::text = (storage.foldername(name))[1]);
