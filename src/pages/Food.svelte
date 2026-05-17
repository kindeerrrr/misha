<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../lib/supabase'
  import { user } from '../stores/user'
  import PageShell from '../components/layout/PageShell.svelte'
  import Modal from '../components/ui/Modal.svelte'

  // ── Types ──────────────────────────────────────────────────────────────────
  interface FoodItem {
    id: string
    name: string
    calories_per_100g: number | null
    protein_per_100g: number | null
    fat_per_100g: number | null
    carbs_per_100g: number | null
  }

  interface FoodEntry {
    id: string
    date: string
    meal_type: string
    food_name: string
    grams: number
    calories: number | null
    protein: number | null
    fat: number | null
    carbs: number | null
    notes: string | null
  }

  // ── State ──────────────────────────────────────────────────────────────────
  let selectedDate = today()
  let entries: FoodEntry[] = []
  let foodItems: FoodItem[] = []
  let loading = true
  let showModal = false
  let saving = false
  let deletingId: string | null = null

  // Form
  let formMeal: string = 'breakfast'
  let formName: string = ''
  let formGrams: number | null = null
  let formCalories: number | null = null
  let formProtein: number | null = null
  let formFat: number | null = null
  let formCarbs: number | null = null
  let suggestions: FoodItem[] = []
  let selectedItem: FoodItem | null = null

  const CALORIE_GOAL = 1800

  const MEAL_TYPES: { id: string; label: string; icon: string }[] = [
    { id: 'breakfast', label: 'Завтрак', icon: '🌅' },
    { id: 'lunch',     label: 'Обед',    icon: '☀️' },
    { id: 'dinner',    label: 'Ужин',    icon: '🌙' },
    { id: 'snack',     label: 'Перекус', icon: '🍪' },
    { id: 'other',     label: 'Другое',  icon: '🍽️' },
  ]

  function mealLabel(id: string): string {
    return MEAL_TYPES.find(m => m.id === id)?.label ?? id
  }

  function mealIcon(id: string): string {
    return MEAL_TYPES.find(m => m.id === id)?.icon ?? '🍽️'
  }

  // ── Derived ────────────────────────────────────────────────────────────────
  $: totalCalories = entries.reduce((s, e) => s + (e.calories ?? 0), 0)
  $: totalProtein  = entries.reduce((s, e) => s + (e.protein ?? 0), 0)
  $: totalFat      = entries.reduce((s, e) => s + (e.fat ?? 0), 0)
  $: totalCarbs    = entries.reduce((s, e) => s + (e.carbs ?? 0), 0)
  $: caloriesPct   = Math.min(100, Math.round((totalCalories / CALORIE_GOAL) * 100))

  $: groupedEntries = MEAL_TYPES.map(m => ({
    ...m,
    items: entries.filter(e => e.meal_type === m.id),
  })).filter(m => m.items.length > 0)

  // ── Date helpers ──────────────────────────────────────────────────────────
  function prevDay() {
    const d = new Date(selectedDate + 'T00:00:00')
    d.setDate(d.getDate() - 1)
    selectedDate = d.toISOString().slice(0, 10)
  }

  function nextDay() {
    const d = new Date(selectedDate + 'T00:00:00')
    d.setDate(d.getDate() + 1)
    const t = today()
    if (d.toISOString().slice(0, 10) <= t) {
      selectedDate = d.toISOString().slice(0, 10)
    }
  }

  function isToday(d: string) { return d === today() }

  function formatDateHeader(d: string): string {
    if (isToday(d)) return 'Сегодня'
    const dt = new Date(d + 'T00:00:00')
    return dt.toLocaleDateString('ru', { weekday: 'short', day: 'numeric', month: 'short' })
  }

  // ── Load ───────────────────────────────────────────────────────────────────
  async function load() {
    if (!$user) return
    loading = true
    const [entRes, itemsRes] = await Promise.all([
      supabase.from('food_entries').select('*').eq('user_id', $user.id).eq('date', selectedDate).order('created_at'),
      supabase.from('food_items').select('id, name, calories_per_100g, protein_per_100g, fat_per_100g, carbs_per_100g').eq('user_id', $user.id).order('name'),
    ])
    entries = entRes.data ?? []
    foodItems = itemsRes.data ?? []
    loading = false
  }

  $: if (selectedDate) load()

  // ── Autocomplete ──────────────────────────────────────────────────────────
  function onNameInput() {
    selectedItem = null
    const q = formName.trim().toLowerCase()
    if (q.length < 1) { suggestions = []; return }
    suggestions = foodItems.filter(i => i.name.toLowerCase().includes(q)).slice(0, 6)
  }

  function selectSuggestion(item: FoodItem) {
    selectedItem = item
    formName = item.name
    suggestions = []
    recalcMacros()
  }

  function recalcMacros() {
    if (!selectedItem || !formGrams) return
    const g = formGrams / 100
    formCalories = selectedItem.calories_per_100g != null ? Math.round(selectedItem.calories_per_100g * g) : formCalories
    formProtein  = selectedItem.protein_per_100g  != null ? Math.round(selectedItem.protein_per_100g  * g * 10) / 10 : formProtein
    formFat      = selectedItem.fat_per_100g      != null ? Math.round(selectedItem.fat_per_100g      * g * 10) / 10 : formFat
    formCarbs    = selectedItem.carbs_per_100g    != null ? Math.round(selectedItem.carbs_per_100g    * g * 10) / 10 : formCarbs
  }

  $: if (formGrams) recalcMacros()

  // ── Save ───────────────────────────────────────────────────────────────────
  async function saveEntry() {
    if (!$user || !formName.trim() || !formGrams) return
    saving = true
    try {
      // Upsert food_item if new name
      let foodItemId: string | null = selectedItem?.id ?? null
      if (!selectedItem) {
        const existing = foodItems.find(i => i.name.toLowerCase() === formName.trim().toLowerCase())
        if (existing) {
          foodItemId = existing.id
        } else if (formCalories && formGrams) {
          const { data: newItem } = await supabase.from('food_items').insert({
            user_id: $user.id,
            name: formName.trim(),
            calories_per_100g: formGrams ? Math.round((formCalories / formGrams) * 100) : null,
            protein_per_100g:  formGrams && formProtein ? Math.round((formProtein  / formGrams) * 100 * 10) / 10 : null,
            fat_per_100g:      formGrams && formFat     ? Math.round((formFat      / formGrams) * 100 * 10) / 10 : null,
            carbs_per_100g:    formGrams && formCarbs   ? Math.round((formCarbs    / formGrams) * 100 * 10) / 10 : null,
          }).select().single()
          if (newItem) foodItemId = newItem.id
        }
      }

      const { data } = await supabase.from('food_entries').insert({
        user_id: $user.id,
        date: selectedDate,
        meal_type: formMeal,
        food_item_id: foodItemId,
        food_name: formName.trim(),
        grams: formGrams,
        calories: formCalories,
        protein: formProtein,
        fat: formFat,
        carbs: formCarbs,
      }).select().single()

      if (data) entries = [...entries, data]
      closeModal()
    } finally {
      saving = false
    }
  }

  async function deleteEntry(id: string) {
    if (!$user) return
    deletingId = id
    await supabase.from('food_entries').delete().eq('id', id).eq('user_id', $user.id)
    entries = entries.filter(e => e.id !== id)
    deletingId = null
  }

  function openModal() {
    formMeal = 'breakfast'
    formName = ''
    formGrams = null
    formCalories = null
    formProtein = null
    formFat = null
    formCarbs = null
    selectedItem = null
    suggestions = []
    showModal = true
  }

  function closeModal() {
    showModal = false
    suggestions = []
  }

  function fmt(n: number | null): string {
    if (n == null) return '—'
    return Math.round(n).toString()
  }

  onMount(load)
</script>

<PageShell title="Питание" subtitle={formatDateHeader(selectedDate)}>
  <svelte:fragment slot="action">
    <div class="date-nav-btns">
      <button class="nav-btn" on:click={prevDay} aria-label="Предыдущий день">‹</button>
      <button class="nav-btn" on:click={nextDay} disabled={isToday(selectedDate)} aria-label="Следующий день">›</button>
    </div>
  </svelte:fragment>

  {#if loading}
    <div class="skeleton-list">
      {#each [1,2,3] as _}<div class="skeleton-card" />{/each}
    </div>
  {:else}
    <!-- Calorie summary -->
    <div class="card summary-card">
      <div class="summary-row">
        <div class="summary-main">
          <span class="cal-value number-display">{fmt(totalCalories)}</span>
          <span class="cal-goal">/ {CALORIE_GOAL} ккал</span>
        </div>
        <span class="cal-pct">{caloriesPct}%</span>
      </div>
      <div class="progress-track">
        <div class="progress-fill" style="width: {caloriesPct}%" />
      </div>
      <div class="macros-row">
        <div class="macro-chip">
          <span class="macro-val">{fmt(totalProtein)}г</span>
          <span class="macro-lbl">белки</span>
        </div>
        <div class="macro-chip">
          <span class="macro-val">{fmt(totalFat)}г</span>
          <span class="macro-lbl">жиры</span>
        </div>
        <div class="macro-chip">
          <span class="macro-val">{fmt(totalCarbs)}г</span>
          <span class="macro-lbl">углев.</span>
        </div>
      </div>
    </div>

    <!-- Meal groups -->
    {#if groupedEntries.length === 0}
      <div class="empty-state">
        <p class="empty-hint">Записей нет. Нажми + чтобы добавить.</p>
      </div>
    {:else}
      {#each groupedEntries as group}
        <div class="meal-section">
          <p class="meal-header">
            <span class="meal-icon">{group.icon}</span>
            {group.label}
            <span class="meal-cal">{fmt(group.items.reduce((s, e) => s + (e.calories ?? 0), 0))} ккал</span>
          </p>
          <div class="card">
            {#each group.items as entry}
              <div class="entry-row" class:fading={deletingId === entry.id}>
                <div class="entry-info">
                  <span class="entry-name">{entry.food_name}</span>
                  <span class="entry-meta">{entry.grams}г{entry.calories != null ? ` · ${fmt(entry.calories)} ккал` : ''}</span>
                </div>
                <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
                <button class="del-btn" on:click={() => deleteEntry(entry.id)} aria-label="Удалить">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" width="16" height="16"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a1 1 0 011-1h4a1 1 0 011 1v2"/></svg>
                </button>
              </div>
            {/each}
          </div>
        </div>
      {/each}
    {/if}
  {/if}
</PageShell>

<!-- FAB -->
<!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
<button class="fab" on:click={openModal} aria-label="Добавить запись">+</button>

<!-- Add entry modal -->
<Modal title="Добавить приём пищи" open={showModal} on:close={closeModal}>
  <!-- Meal type selector -->
  <div class="form-field">
    <label class="form-label">Приём пищи</label>
    <div class="meal-selector">
      {#each MEAL_TYPES as m}
        <button
          class="meal-sel-btn"
          class:active={formMeal === m.id}
          on:click={() => formMeal = m.id}
        >{m.icon} {m.label}</button>
      {/each}
    </div>
  </div>

  <!-- Food name with autocomplete -->
  <div class="form-field autocomplete-wrap">
    <label class="form-label" for="food-name">Название</label>
    <input
      id="food-name"
      class="form-input"
      type="text"
      placeholder="Гречка, куриная грудка…"
      bind:value={formName}
      on:input={onNameInput}
      autocomplete="off"
    />
    {#if suggestions.length > 0}
      <div class="suggestions">
        {#each suggestions as s}
          <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
          <div class="suggestion-row" on:click={() => selectSuggestion(s)}>
            <span class="sug-name">{s.name}</span>
            {#if s.calories_per_100g}
              <span class="sug-cal">{s.calories_per_100g} ккал/100г</span>
            {/if}
          </div>
        {/each}
      </div>
    {/if}
  </div>

  <!-- Grams -->
  <div class="form-row">
    <div class="form-field">
      <label class="form-label" for="food-grams">Граммы</label>
      <input
        id="food-grams"
        class="form-input"
        type="number"
        inputmode="decimal"
        placeholder="100"
        bind:value={formGrams}
        min="1"
      />
    </div>
    <div class="form-field">
      <label class="form-label" for="food-cal">Калории</label>
      <input
        id="food-cal"
        class="form-input"
        type="number"
        inputmode="decimal"
        placeholder="авто"
        bind:value={formCalories}
        min="0"
      />
    </div>
  </div>

  <!-- Macros (optional) -->
  <div class="form-row">
    <div class="form-field">
      <label class="form-label" for="food-p">Белки (г)</label>
      <input id="food-p" class="form-input" type="number" inputmode="decimal" placeholder="—" bind:value={formProtein} min="0" />
    </div>
    <div class="form-field">
      <label class="form-label" for="food-f">Жиры (г)</label>
      <input id="food-f" class="form-input" type="number" inputmode="decimal" placeholder="—" bind:value={formFat} min="0" />
    </div>
    <div class="form-field">
      <label class="form-label" for="food-c">Углев. (г)</label>
      <input id="food-c" class="form-input" type="number" inputmode="decimal" placeholder="—" bind:value={formCarbs} min="0" />
    </div>
  </div>

  <button
    class="save-btn"
    disabled={saving || !formName.trim() || !formGrams}
    on:click={saveEntry}
  >
    {saving ? 'Сохраняю…' : 'Сохранить'}
  </button>
</Modal>

<style>
  /* ── Date nav buttons in header slot ── */
  .date-nav-btns {
    display: flex;
    gap: 0.25rem;
    margin-top: 0.125rem;
  }

  .nav-btn {
    width: 2rem;
    height: 2rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.5rem;
    color: var(--color-text);
    font-size: 1.125rem;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    -webkit-tap-highlight-color: transparent;
  }

  .nav-btn:disabled { opacity: 0.35; cursor: default; }

  /* ── Summary card ── */
  .card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    padding: 0.875rem 1rem;
  }

  .summary-card { margin-bottom: 1.25rem; }

  .summary-row {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    margin-bottom: 0.625rem;
  }

  .summary-main { display: flex; align-items: baseline; gap: 0.375rem; }

  .cal-value {
    font-family: "JetBrains Mono", monospace;
    font-size: 1.75rem;
    color: var(--color-text);
  }

  .cal-goal { font-size: 0.875rem; color: var(--color-muted); }

  .cal-pct {
    font-family: "JetBrains Mono", monospace;
    font-size: 1rem;
    color: var(--color-accent);
  }

  .progress-track {
    height: 6px;
    background: var(--color-bg);
    border-radius: 3px;
    overflow: hidden;
    margin-bottom: 0.75rem;
  }

  .progress-fill {
    height: 100%;
    background: var(--color-accent);
    border-radius: 3px;
    transition: width 0.4s ease;
  }

  .macros-row {
    display: flex;
    gap: 0.5rem;
  }

  .macro-chip {
    flex: 1;
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    padding: 0.375rem 0.5rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
  }

  .macro-val {
    font-family: "JetBrains Mono", monospace;
    font-size: 0.9375rem;
    color: var(--color-text);
  }

  .macro-lbl {
    font-size: 0.625rem;
    color: var(--color-muted);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  /* ── Meal sections ── */
  .meal-section { margin-bottom: 1rem; }

  .meal-header {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    font-size: 0.8125rem;
    font-weight: 500;
    color: var(--color-text);
    margin: 0 0 0.375rem 0.25rem;
  }

  .meal-icon { font-size: 1rem; }

  .meal-cal {
    margin-left: auto;
    font-family: "JetBrains Mono", monospace;
    font-size: 0.75rem;
    color: var(--color-muted);
  }

  .entry-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 0;
    border-bottom: 1px solid var(--color-border);
    transition: opacity 0.2s;
  }

  .entry-row:last-child { border-bottom: none; }
  .entry-row.fading { opacity: 0.4; }

  .entry-info { flex: 1; display: flex; flex-direction: column; gap: 1px; }

  .entry-name { font-size: 0.9375rem; color: var(--color-text); }

  .entry-meta { font-size: 0.75rem; color: var(--color-muted); }

  .del-btn {
    background: none;
    border: none;
    color: var(--color-muted);
    cursor: pointer;
    padding: 0.25rem;
    -webkit-tap-highlight-color: transparent;
    border-radius: 0.5rem;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: color 0.15s;
  }

  .del-btn:active { color: #e53e3e; }

  /* ── Empty ── */
  .empty-state {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 2.5rem 0;
  }

  .empty-hint { font-size: 0.875rem; color: var(--color-muted); margin: 0; text-align: center; }

  /* ── FAB ── */
  .fab {
    position: fixed;
    bottom: calc(4.5rem + env(safe-area-inset-bottom));
    right: 1.25rem;
    width: 3.25rem;
    height: 3.25rem;
    border-radius: 50%;
    background: var(--color-accent);
    color: white;
    border: none;
    font-size: 1.75rem;
    line-height: 1;
    cursor: pointer;
    box-shadow: 0 4px 16px rgba(0,0,0,0.18);
    display: flex;
    align-items: center;
    justify-content: center;
    -webkit-tap-highlight-color: transparent;
    transition: transform 0.15s, opacity 0.15s;
    z-index: 50;
  }

  .fab:active { transform: scale(0.92); opacity: 0.85; }

  /* ── Modal form ── */
  .form-field {
    margin-bottom: 1rem;
    position: relative;
  }

  .form-label {
    display: block;
    font-size: 0.75rem;
    color: var(--color-muted);
    margin-bottom: 0.375rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .form-input {
    width: 100%;
    padding: 0.625rem 0.875rem;
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    color: var(--color-text);
    font-size: 1rem;
    font-family: inherit;
    box-sizing: border-box;
    -webkit-appearance: none;
  }

  .form-input:focus {
    outline: none;
    border-color: var(--color-accent);
  }

  .form-row {
    display: flex;
    gap: 0.625rem;
    margin-bottom: 0;
  }

  .form-row .form-field { flex: 1; }

  .meal-selector {
    display: flex;
    flex-wrap: wrap;
    gap: 0.375rem;
  }

  .meal-sel-btn {
    padding: 0.375rem 0.75rem;
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 2rem;
    color: var(--color-text);
    font-size: 0.8125rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
  }

  .meal-sel-btn.active {
    background: var(--color-accent);
    border-color: var(--color-accent);
    color: white;
  }

  .autocomplete-wrap { z-index: 10; }

  .suggestions {
    position: absolute;
    top: 100%;
    left: 0;
    right: 0;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    box-shadow: 0 4px 20px rgba(0,0,0,0.1);
    z-index: 100;
    overflow: hidden;
    margin-top: 2px;
  }

  .suggestion-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.625rem 0.875rem;
    cursor: pointer;
    border-bottom: 1px solid var(--color-border);
    -webkit-tap-highlight-color: transparent;
  }

  .suggestion-row:last-child { border-bottom: none; }
  .suggestion-row:active { background: var(--color-bg); }

  .sug-name { font-size: 0.9375rem; color: var(--color-text); }
  .sug-cal { font-size: 0.75rem; color: var(--color-muted); }

  .save-btn {
    width: 100%;
    padding: 0.875rem;
    background: var(--color-accent);
    color: white;
    border: none;
    border-radius: 1rem;
    font-size: 1rem;
    font-family: inherit;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    margin-top: 0.5rem;
    transition: opacity 0.15s;
  }

  .save-btn:disabled { opacity: 0.5; cursor: default; }

  /* ── Skeleton ── */
  .skeleton-list { display: flex; flex-direction: column; gap: 0.75rem; }
  .skeleton-card {
    height: 5rem;
    border-radius: 1.25rem;
    background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover, var(--color-border)) 50%, var(--color-card) 75%);
    background-size: 200% 100%;
    animation: shimmer 1.4s infinite;
  }

  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }
</style>
