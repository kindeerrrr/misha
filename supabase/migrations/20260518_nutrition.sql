-- ─────────────────────────────────────────────────────────────────────────────
-- Nutrition module — full schema
-- Run once in Supabase SQL editor
-- ─────────────────────────────────────────────────────────────────────────────

-- ── nutrition_foods ───────────────────────────────────────────────────────────
-- Global cache (user_id IS NULL) + user's custom foods
create table if not exists nutrition_foods (
  id                uuid    primary key default gen_random_uuid(),
  user_id           uuid    references auth.users(id) on delete cascade,
  fatsecret_id      text,
  name              text    not null,
  brand             text,
  calories_per_100g numeric,
  protein_per_100g  numeric,
  fat_per_100g      numeric,
  carbs_per_100g    numeric,
  -- [{ "name": "1 яйцо", "grams": 50 }]
  servings          jsonb   default '[]',
  -- [{ "name": "сухая", "coefficient": 1 }, { "name": "варёная", "coefficient": 2.8 }]
  states            jsonb   default '[]',
  barcode           text,
  allergens         text[],
  created_at        timestamptz default now()
);
create unique index if not exists nutrition_foods_fatsecret_idx
  on nutrition_foods (fatsecret_id)
  where fatsecret_id is not null;
create index if not exists nutrition_foods_barcode_idx
  on nutrition_foods (barcode)
  where barcode is not null;
create index if not exists nutrition_foods_user_idx
  on nutrition_foods (user_id);

-- ── nutrition_entries ─────────────────────────────────────────────────────────
create table if not exists nutrition_entries (
  id         uuid    primary key default gen_random_uuid(),
  user_id    uuid    references auth.users(id) on delete cascade not null,
  date       date    not null,
  meal       text    not null check (meal in ('breakfast','lunch','dinner','snack')),
  food_id    uuid    references nutrition_foods(id),
  food_name  text    not null,
  amount     numeric not null,
  unit       text    not null default 'г',
  state      text,              -- 'сухая' / 'варёная' etc.
  calories   numeric,
  protein    numeric,
  fat        numeric,
  carbs      numeric,
  notes      text,
  created_at timestamptz default now()
);
create index if not exists nutrition_entries_user_date_idx
  on nutrition_entries (user_id, date);

-- ── nutrition_saved_meals ─────────────────────────────────────────────────────
create table if not exists nutrition_saved_meals (
  id          uuid  primary key default gen_random_uuid(),
  user_id     uuid  references auth.users(id) on delete cascade not null,
  name        text  not null,
  -- [{ "food_id": "...", "food_name": "...", "amount": 150, "unit": "г" }]
  ingredients jsonb not null default '[]',
  created_at  timestamptz default now()
);
create index if not exists nutrition_saved_meals_user_idx
  on nutrition_saved_meals (user_id);

-- ── nutrition_goals ───────────────────────────────────────────────────────────
create table if not exists nutrition_goals (
  user_id         uuid    primary key references auth.users(id) on delete cascade,
  daily_calories  integer default 1600,
  daily_protein_g integer default 90,
  daily_fat_g     integer default 55,
  daily_carbs_g   integer default 180,
  updated_at      timestamptz default now()
);

-- ── RLS ───────────────────────────────────────────────────────────────────────
alter table nutrition_foods       enable row level security;
alter table nutrition_entries     enable row level security;
alter table nutrition_saved_meals enable row level security;
alter table nutrition_goals       enable row level security;

-- nutrition_foods: global (null user_id) visible to everyone; own rows editable
drop policy if exists "nf_select" on nutrition_foods;
create policy "nf_select" on nutrition_foods
  for select using (user_id is null or user_id = auth.uid());

drop policy if exists "nf_insert" on nutrition_foods;
create policy "nf_insert" on nutrition_foods
  for insert with check (user_id = auth.uid() or user_id is null);

drop policy if exists "nf_update" on nutrition_foods;
create policy "nf_update" on nutrition_foods
  for update using (user_id = auth.uid());

drop policy if exists "nf_delete" on nutrition_foods;
create policy "nf_delete" on nutrition_foods
  for delete using (user_id = auth.uid());

-- Other tables: own rows only
drop policy if exists "ne_all" on nutrition_entries;
create policy "ne_all" on nutrition_entries
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "nsm_all" on nutrition_saved_meals;
create policy "nsm_all" on nutrition_saved_meals
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "ng_all" on nutrition_goals;
create policy "ng_all" on nutrition_goals
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── Migrate existing food_entries → nutrition_entries ────────────────────────
-- Run only if food_entries table exists
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'food_entries'
  ) then
    insert into nutrition_entries
      (user_id, date, meal, food_name, amount, unit, calories, protein, fat, carbs, created_at)
    select
      user_id,
      date,
      meal_type,
      food_name,
      coalesce(grams, 100),
      'г',
      calories,
      protein,
      fat,
      carbs,
      created_at
    from food_entries fe
    where not exists (
      select 1 from nutrition_entries ne
      where ne.user_id    = fe.user_id
        and ne.date       = fe.date
        and ne.food_name  = fe.food_name
        and ne.created_at = fe.created_at
    );
  end if;
end $$;
