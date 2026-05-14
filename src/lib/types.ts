// ─── Auth ────────────────────────────────────────────────────────────────────

export interface Profile {
  id: string
  email: string
  created_at: string
}

// ─── Medications ─────────────────────────────────────────────────────────────

export type MedicationFrequency = 'daily' | 'twice_daily' | 'weekdays' | 'weekly' | 'custom'
export type MedicationCriticality = 'high' | 'medium' | 'low'
export type MedicationStatus = 'active' | 'paused' | 'planned'

export interface Medication {
  id: string
  user_id: string
  name: string
  frequency: MedicationFrequency
  time_of_day: string | null       // e.g. "evening", "09:00"
  criticality: MedicationCriticality
  status: MedicationStatus
  notes: string | null
  created_at: string
}

export interface MedicationLog {
  id: string
  user_id: string
  medication_id: string
  taken_at: string
  skipped: boolean
  skip_reason: string | null
  date: string                     // YYYY-MM-DD
}

// ─── Sleep ───────────────────────────────────────────────────────────────────

export interface SleepLog {
  id: string
  user_id: string
  date: string                     // YYYY-MM-DD (the morning date)
  bedtime: string | null           // ISO timestamp
  wake_time: string | null         // ISO timestamp
  duration_minutes: number | null
  quality: number | null           // 1–5
  notes: string | null
  created_at: string
}

// ─── Measurements ────────────────────────────────────────────────────────────

export interface DailyWeight {
  id: string
  user_id: string
  date: string
  weight_kg: number
  created_at: string
}

export interface WeeklyMeasurement {
  id: string
  user_id: string
  date: string
  weight_kg: number | null
  water_pct: number | null
  muscle_pct: number | null
  fat_pct: number | null
  bone_kg: number | null
  chest_cm: number | null
  waist_cm: number | null
  hips_cm: number | null
  created_at: string
}

// ─── Workouts ────────────────────────────────────────────────────────────────

export interface WorkoutType {
  id: string
  user_id: string
  name: string
  icon: string | null
  is_default: boolean
  created_at: string
}

export interface WorkoutLog {
  id: string
  user_id: string
  workout_type_id: string
  workout_type?: WorkoutType
  date: string
  duration_minutes: number
  intensity: number | null        // 1–5
  notes: string | null
  created_at: string
}

// ─── Doctors ─────────────────────────────────────────────────────────────────

export interface DoctorVisit {
  id: string
  user_id: string
  date: string
  doctor_category: string          // e.g. "Стоматолог"
  procedure: string                // e.g. "Чистка"
  notes: string | null
  file_urls: string[]
  created_at: string
}

export interface MedicalResearch {
  id: string
  user_id: string
  date: string
  research_type: string            // УЗИ, МРТ, КТ, ЭКГ…
  body_part: string | null
  description: string | null
  file_urls: string[]
  created_at: string
}

// ─── Annual Checkups ─────────────────────────────────────────────────────────

export interface AnnualCheckup {
  id: string
  user_id: string
  name: string
  frequency_months: number
  last_done_at: string | null
  next_due_at: string | null
  reminder_2w: boolean
  reminder_3d: boolean
  notes: string | null
  created_at: string
}

// ─── Emotions ────────────────────────────────────────────────────────────────

export interface EmotionEntry {
  id: string
  user_id: string
  recorded_at: string
  date: string
  emoji: string
  note: string | null
  created_at: string
}

export interface DayReport {
  id: string
  user_id: string
  date: string
  overall: number | null           // 1–5
  energy: number | null
  anxiety: number | null
  productivity: number | null
  warmth: number | null
  highlight: string | null
  low_point: string | null
  gratitude: string | null
  created_at: string
}

// ─── Finances ────────────────────────────────────────────────────────────────

export interface ExpenseCategory {
  id: string
  user_id: string
  name: string
  emoji: string
  group_name: string
  is_quick: boolean
  sort_order: number
}

export interface Expense {
  id: string
  user_id: string
  date: string
  amount: number
  category_id: string | null
  category?: ExpenseCategory
  note: string | null
  tx_type: 'expense' | 'income' | 'saving'
  created_at: string
}

// ─── Habits ──────────────────────────────────────────────────────────────────

export interface Habit {
  id: string
  user_id: string
  name: string
  color: string | null
  sort_order: number
  archived: boolean
  created_at: string
}

export interface HabitLog {
  id: string
  user_id: string
  habit_id: string
  date: string
  created_at: string
}

// ─── Cat ─────────────────────────────────────────────────────────────────────

export interface CatProfile {
  id: string
  user_id: string
  name: string
  breed: string | null
  birth_date: string | null
  weight_kg: number | null
  notes: string | null
  animal_type: string | null
  photo_url: string | null
  coat_color: string | null
}

export interface CatVaccine {
  id: string
  user_id: string
  cat_id: string | null
  name: string
  date: string
  next_due: string | null
  clinic: string | null
  notes: string | null
  created_at: string
}

export interface CatHealthEvent {
  id: string
  user_id: string
  cat_id: string | null
  date: string
  description: string
  vet_visit: boolean
  category: string | null
  created_at: string
}

export interface CatGrooming {
  id: string
  user_id: string
  cat_id: string | null
  date: string
  type: string
  next_due: string | null
  notes: string | null
  created_at: string
}

export interface CatFoodOrder {
  id: string
  user_id: string
  cat_id: string | null
  date: string
  brand: string
  product: string
  quantity: string | null
  price: number | null
  next_order: string | null
  created_at: string
}

// ─── Media ───────────────────────────────────────────────────────────────────

export type MediaType = 'book' | 'film' | 'series'
export type MediaStatus = 'want' | 'in_progress' | 'done'

export interface MediaItem {
  id: string
  user_id: string
  title: string
  type: MediaType
  genre: string | null
  status: MediaStatus
  rating: number | null
  notes: string | null
  started_at: string | null
  finished_at: string | null
  total_pages: number | null
  current_page: number | null
  seasons_total: number | null
  current_season: number | null
  current_episode: number | null
  is_finished: boolean
  created_at: string
}

// ─── Credits ─────────────────────────────────────────────────────────────────

export interface Credit {
  id: string
  user_id: string
  name: string
  total_amount: number
  remaining: number
  monthly_payment: number | null
  payment_day: number | null
  start_date: string
  end_date: string | null
  notes: string | null
  created_at: string
}

export interface CreditPayment {
  id: string
  user_id: string
  credit_id: string
  date: string
  amount: number
  paid: boolean
  notes: string | null
  created_at: string
}

// ─── UI helpers ──────────────────────────────────────────────────────────────

export type Theme = 'latte' | 'sage' | 'light' | 'dark'
export type NavTab = 'dashboard' | 'health' | 'emotions' | 'finances' | 'habits' | 'cat' | 'media' | 'settings' | 'hub'
export type HealthTab = 'hub' | 'pills' | 'sleep' | 'measurements' | 'workouts' | 'doctors' | 'research' | 'checkups'
