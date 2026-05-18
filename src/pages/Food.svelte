<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import { supabase, today } from '../lib/supabase'
  import { user } from '../stores/user'
  import PageShell from '../components/layout/PageShell.svelte'
  import Modal from '../components/ui/Modal.svelte'

  // ── Worker URL (set via CF Pages env var) ─────────────────────────────────
  const FS_WORKER = import.meta.env.VITE_FATSECRET_WORKER_URL ?? ''

  // ── Types ─────────────────────────────────────────────────────────────────
  interface FoodItem {
    id: string
    name: string
    calories_per_100g: number | null
    protein_per_100g:  number | null
    fat_per_100g:      number | null
    carbs_per_100g:    number | null
  }

  interface FoodEntry {
    id: string
    date: string
    meal_type: string
    food_name: string
    grams: number
    calories: number | null
    protein:  number | null
    fat:      number | null
    carbs:    number | null
    notes:    string | null
  }

  type SuggSource = 'local' | 'fatsecret'

  interface Suggestion {
    id: string
    name: string
    brand: string | null
    calories_per_100g: number | null
    protein_per_100g:  number | null
    fat_per_100g:      number | null
    carbs_per_100g:    number | null
    source: SuggSource
  }

  // ── State ─────────────────────────────────────────────────────────────────
  let selectedDate = today()
  let entries:   FoodEntry[] = []
  let foodItems: FoodItem[]  = []
  let loading = true
  let showModal = false
  let saving    = false
  let deletingId: string | null = null

  const CALORIE_GOAL = 1800

  const MEAL_TYPES: { id: string; label: string; icon: string }[] = [
    { id: 'breakfast', label: 'Завтрак', icon: '🌅' },
    { id: 'lunch',     label: 'Обед',    icon: '☀️'  },
    { id: 'dinner',    label: 'Ужин',    icon: '🌙'  },
    { id: 'snack',     label: 'Перекус', icon: '🍪'  },
    { id: 'other',     label: 'Другое',  icon: '🍽️' },
  ]

  function mealLabel(id: string) { return MEAL_TYPES.find(m => m.id === id)?.label ?? id }
  function mealIcon(id: string)  { return MEAL_TYPES.find(m => m.id === id)?.icon  ?? '🍽️' }

  // ── Form ──────────────────────────────────────────────────────────────────
  let formMeal:     string = 'breakfast'
  let formName:     string = ''
  let formGrams:    number | null = null
  let formCalories: number | null = null
  let formProtein:  number | null = null
  let formFat:      number | null = null
  let formCarbs:    number | null = null

  // Active suggestion (applied macros)
  let pickedItem: Suggestion | null = null

  // Merged suggestion list (local + FatSecret)
  let suggestions: Suggestion[] = []
  let fsSearching = false
  let fsTimer: ReturnType<typeof setTimeout> | null = null

  // ── Scanner ───────────────────────────────────────────────────────────────
  let scanning      = false
  let barcodeStatus = ''          // '' | 'searching' | 'found' | 'notfound' | 'error'
  let scannerVideoEl: HTMLVideoElement | null = null
  let scannerControls: { stop: () => void } | null = null

  // ── Derived ───────────────────────────────────────────────────────────────
  $: totalCalories = entries.reduce((s, e) => s + (e.calories ?? 0), 0)
  $: totalProtein  = entries.reduce((s, e) => s + (e.protein  ?? 0), 0)
  $: totalFat      = entries.reduce((s, e) => s + (e.fat      ?? 0), 0)
  $: totalCarbs    = entries.reduce((s, e) => s + (e.carbs    ?? 0), 0)
  $: caloriesPct   = Math.min(100, Math.round((totalCalories / CALORIE_GOAL) * 100))

  $: groupedEntries = MEAL_TYPES
    .map(m => ({ ...m, items: entries.filter(e => e.meal_type === m.id) }))
    .filter(m => m.items.length > 0)

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
    if (d.toISOString().slice(0, 10) <= t) selectedDate = d.toISOString().slice(0, 10)
  }
  function isToday(d: string) { return d === today() }
  function formatDateHeader(d: string): string {
    if (isToday(d)) return 'Сегодня'
    return new Date(d + 'T00:00:00').toLocaleDateString('ru', { weekday: 'short', day: 'numeric', month: 'short' })
  }

  // ── Load ──────────────────────────────────────────────────────────────────
  async function load() {
    if (!$user) return
    loading = true
    const [entRes, itemsRes] = await Promise.all([
      supabase.from('food_entries').select('*')
        .eq('user_id', $user.id).eq('date', selectedDate).order('created_at'),
      supabase.from('food_items').select('id, name, calories_per_100g, protein_per_100g, fat_per_100g, carbs_per_100g')
        .eq('user_id', $user.id).order('name'),
    ])
    entries   = entRes.data   ?? []
    foodItems = itemsRes.data ?? []
    loading   = false
  }

  $: if (selectedDate) load()

  // ── Local autocomplete ────────────────────────────────────────────────────
  function localSuggestions(q: string): Suggestion[] {
    return foodItems
      .filter(i => i.name.toLowerCase().includes(q))
      .slice(0, 4)
      .map(i => ({
        id: i.id, name: i.name, brand: null,
        calories_per_100g: i.calories_per_100g,
        protein_per_100g:  i.protein_per_100g,
        fat_per_100g:      i.fat_per_100g,
        carbs_per_100g:    i.carbs_per_100g,
        source: 'local' as SuggSource,
      }))
  }

  // ── FatSecret search ──────────────────────────────────────────────────────
  async function searchFatSecret(q: string): Promise<Suggestion[]> {
    if (!FS_WORKER) return []
    try {
      fsSearching = true
      const res = await fetch(`${FS_WORKER}/search?q=${encodeURIComponent(q)}`)
      if (!res.ok) return []
      const data = await res.json()
      return (data.results ?? []).map((f: {
        id: string; name: string; brand: string | null;
        calories_per_100g?: number; protein_per_100g?: number;
        fat_per_100g?: number; carbs_per_100g?: number;
      }) => ({
        id: `fs-${f.id}`,
        name: f.brand ? `${f.name} (${f.brand})` : f.name,
        brand: f.brand,
        calories_per_100g: f.calories_per_100g ?? null,
        protein_per_100g:  f.protein_per_100g  ?? null,
        fat_per_100g:      f.fat_per_100g      ?? null,
        carbs_per_100g:    f.carbs_per_100g    ?? null,
        source: 'fatsecret' as SuggSource,
      }))
    } catch {
      return []
    } finally {
      fsSearching = false
    }
  }

  function onNameInput() {
    pickedItem = null
    const q = formName.trim().toLowerCase()
    if (q.length < 1) { suggestions = []; return }

    // Immediately show local results
    suggestions = localSuggestions(q)

    // Debounced FatSecret search
    if (fsTimer) clearTimeout(fsTimer)
    if (FS_WORKER) {
      fsTimer = setTimeout(async () => {
        const fsSuggs = await searchFatSecret(q)
        // Deduplicate against local by lowercase name
        const localNames = new Set(suggestions.map(s => s.name.toLowerCase()))
        const fresh = fsSuggs.filter(s => !localNames.has(s.name.toLowerCase()))
        suggestions = [...suggestions, ...fresh].slice(0, 8)
      }, 420)
    }
  }

  function pickSuggestion(s: Suggestion) {
    pickedItem    = s
    formName      = s.brand ? `${s.name.replace(/ \(.+\)$/, '')}` : s.name
    suggestions   = []
    recalcMacros()
  }

  function recalcMacros() {
    if (!pickedItem || !formGrams) return
    const g = formGrams / 100
    if (pickedItem.calories_per_100g != null) formCalories = Math.round(pickedItem.calories_per_100g * g)
    if (pickedItem.protein_per_100g  != null) formProtein  = Math.round(pickedItem.protein_per_100g  * g * 10) / 10
    if (pickedItem.fat_per_100g      != null) formFat      = Math.round(pickedItem.fat_per_100g      * g * 10) / 10
    if (pickedItem.carbs_per_100g    != null) formCarbs    = Math.round(pickedItem.carbs_per_100g    * g * 10) / 10
  }

  $: if (formGrams) recalcMacros()

  // ── Barcode scanner ───────────────────────────────────────────────────────
  async function startScanner() {
    // Close modal first so scanner gets full screen
    showModal     = false
    scanning      = true
    barcodeStatus = ''
    // Wait for modal to close and video element to mount
    await new Promise(r => setTimeout(r, 180))
    if (!scannerVideoEl) return

    try {
      const { BrowserMultiFormatReader } = await import('@zxing/browser')
      const reader = new BrowserMultiFormatReader()
      scannerControls = await reader.decodeFromVideoDevice(
        undefined,
        scannerVideoEl,
        (result, _err, controls) => {
          if (result) {
            controls.stop()
            scanning = false
            lookupBarcode(result.getText())
          }
        }
      )
    } catch (e) {
      barcodeStatus = 'error'
      scanning = false
      showModal = true   // reopen modal on error so user isn't stuck
      console.error('Scanner error:', e)
    }
  }

  function stopScanner() {
    scannerControls?.stop()
    scannerControls = null
    scanning = false
    barcodeStatus = ''
  }

  // ── Barcode lookup: Open Food Facts → FatSecret ───────────────────────────
  async function lookupBarcode(code: string) {
    barcodeStatus = 'searching'
    // Reset form before filling from barcode
    formName = ''; formGrams = 100; formCalories = null
    formProtein = null; formFat = null; formCarbs = null; pickedItem = null

    // 1) Try Open Food Facts (great Russian product coverage, no auth)
    try {
      const res = await fetch(
        `https://world.openfoodfacts.org/api/v2/product/${code}.json?fields=product_name,product_name_ru,brands,nutriments`
      )
      const data = await res.json()
      if (data.status === 1 && data.product) {
        const p  = data.product
        const n  = p.nutriments ?? {}
        const name = p.product_name_ru || p.product_name || ''

        if (name) {
          formName  = name
          const item: Suggestion = {
            id:    `off-${code}`,
            name,
            brand: p.brands ?? null,
            calories_per_100g: n['energy-kcal_100g'] != null ? Math.round(n['energy-kcal_100g']) : null,
            protein_per_100g:  n.proteins_100g      != null ? Math.round(n.proteins_100g      * 10) / 10 : null,
            fat_per_100g:      n.fat_100g            != null ? Math.round(n.fat_100g            * 10) / 10 : null,
            carbs_per_100g:    n.carbohydrates_100g  != null ? Math.round(n.carbohydrates_100g  * 10) / 10 : null,
            source: 'local',  // treat as local — already have macros
          }
          pickedItem    = item
          formGrams     = formGrams ?? 100
          recalcMacros()
          barcodeStatus = 'found'
          showModal = true
          return
        }
      }
    } catch { /* ignore, fall through */ }

    // 2) Fallback — FatSecret barcode lookup
    if (FS_WORKER) {
      try {
        const res = await fetch(`${FS_WORKER}/barcode?code=${encodeURIComponent(code)}`)
        const data = await res.json()
        if (data.found) {
          const item: Suggestion = {
            id:    `fs-${data.id}`,
            name:  data.name,
            brand: data.brand ?? null,
            calories_per_100g: data.calories_per_100g ?? null,
            protein_per_100g:  data.protein_per_100g  ?? null,
            fat_per_100g:      data.fat_per_100g      ?? null,
            carbs_per_100g:    data.carbs_per_100g    ?? null,
            source: 'fatsecret',
          }
          formName  = item.brand ? `${item.name} (${item.brand})` : item.name
          pickedItem = item
          formGrams  = formGrams ?? 100
          recalcMacros()
          barcodeStatus = 'found'
          showModal = true
          return
        }
      } catch { /* ignore */ }
    }

    barcodeStatus = 'notfound'
    showModal = true
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  async function saveEntry() {
    if (!$user || !formName.trim() || !formGrams) return
    saving = true
    try {
      let foodItemId: string | null = null

      // Persist to food_items only for local (non-FS) items with macros
      if (!pickedItem || pickedItem.source === 'local') {
        const existing = foodItems.find(i =>
          i.name.toLowerCase() === formName.trim().toLowerCase()
        )
        if (existing) {
          foodItemId = existing.id
        } else if (formCalories != null) {
          const { data: newItem } = await supabase.from('food_items').insert({
            user_id: $user.id,
            name:    formName.trim(),
            calories_per_100g: formGrams ? Math.round((formCalories / formGrams) * 100) : null,
            protein_per_100g:  formGrams && formProtein ? Math.round((formProtein  / formGrams) * 100 * 10) / 10 : null,
            fat_per_100g:      formGrams && formFat     ? Math.round((formFat      / formGrams) * 100 * 10) / 10 : null,
            carbs_per_100g:    formGrams && formCarbs   ? Math.round((formCarbs    / formGrams) * 100 * 10) / 10 : null,
          }).select().single()
          if (newItem) {
            foodItemId = newItem.id
            foodItems  = [...foodItems, newItem]
          }
        }
      }

      const { data } = await supabase.from('food_entries').insert({
        user_id:      $user.id,
        date:         selectedDate,
        meal_type:    formMeal,
        food_item_id: foodItemId,
        food_name:    formName.trim(),
        grams:        formGrams,
        calories:     formCalories,
        protein:      formProtein,
        fat:          formFat,
        carbs:        formCarbs,
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
    entries    = entries.filter(e => e.id !== id)
    deletingId = null
  }

  function openModal() {
    formMeal = 'breakfast'; formName = ''; formGrams = null
    formCalories = null; formProtein = null; formFat = null; formCarbs = null
    pickedItem = null; suggestions = []; barcodeStatus = ''
    showModal = true
  }

  function closeModal() {
    stopScanner()
    showModal = false; suggestions = []; barcodeStatus = ''
  }

  function fmt(n: number | null): string {
    if (n == null) return '—'
    return Math.round(n).toString()
  }

  onMount(load)
  onDestroy(() => { stopScanner(); if (fsTimer) clearTimeout(fsTimer) })
</script>

<!-- ── Scanner overlay ─────────────────────────────────────────────────── -->
{#if scanning}
  <div class="scanner-overlay">
    <div class="scanner-inner">
      <p class="scanner-hint">Наведи камеру на штрих-код</p>
      <!-- svelte-ignore a11y-media-has-caption -->
      <video bind:this={scannerVideoEl} class="scanner-video" autoplay playsinline muted />
      <div class="scan-frame">
        <span class="corner tl" /><span class="corner tr" />
        <span class="corner bl" /><span class="corner br" />
        <div class="scan-line" />
      </div>
      <button class="scanner-cancel" on:click={stopScanner}>Отмена</button>
    </div>
  </div>
{/if}

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
                <button class="del-btn" on:click={() => deleteEntry(entry.id)} aria-label="Удалить">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" width="16" height="16">
                    <polyline points="3 6 5 6 21 6"/>
                    <path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/>
                    <path d="M10 11v6M14 11v6"/>
                    <path d="M9 6V4a1 1 0 011-1h4a1 1 0 011 1v2"/>
                  </svg>
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
<button class="fab" on:click={openModal} aria-label="Добавить запись">+</button>

<!-- ── Add entry modal ────────────────────────────────────────────────── -->
<Modal title="Добавить приём пищи" open={showModal} on:close={closeModal}>

  <!-- Barcode status banner -->
  {#if barcodeStatus === 'searching'}
    <div class="barcode-banner searching">🔍 Ищу продукт по штрих-коду…</div>
  {:else if barcodeStatus === 'found'}
    <div class="barcode-banner found">✓ Продукт найден</div>
  {:else if barcodeStatus === 'notfound'}
    <div class="barcode-banner notfound">Продукт не найден — введи вручную</div>
  {/if}

  <!-- Meal type selector -->
  <div class="form-field">
    <label class="form-label">Приём пищи</label>
    <div class="meal-selector">
      {#each MEAL_TYPES as m}
        <button class="meal-sel-btn" class:active={formMeal === m.id}
          on:click={() => formMeal = m.id}>{m.icon} {m.label}</button>
      {/each}
    </div>
  </div>

  <!-- Food name with autocomplete + scan button -->
  <div class="form-field autocomplete-wrap">
    <label class="form-label" for="food-name">Название</label>
    <div class="name-input-wrap">
      <input
        id="food-name"
        class="form-input name-input"
        type="text"
        placeholder="Гречка, куриная грудка…"
        bind:value={formName}
        on:input={onNameInput}
        autocomplete="off"
      />
      <button class="scan-btn" type="button" on:click={startScanner} aria-label="Сканировать штрих-код">
        {#if fsSearching}
          <span class="spin">⟳</span>
        {:else}
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" width="18" height="18">
            <rect x="2" y="2" width="5" height="5" rx="1"/>
            <rect x="17" y="2" width="5" height="5" rx="1"/>
            <rect x="2" y="17" width="5" height="5" rx="1"/>
            <line x1="17" y1="17" x2="22" y2="17"/><line x1="17" y1="17" x2="17" y2="22"/>
            <line x1="2"  y1="9"  x2="2"  y2="9"/><line x1="7"  y1="9"  x2="9"  y2="9"/>
            <line x1="9"  y1="2"  x2="9"  y2="7"/><line x1="12" y1="2"  x2="12" y2="5"/>
            <line x1="12" y1="7"  x2="12" y2="9"/><line x1="15" y1="7"  x2="17" y2="7"/>
            <line x1="12" y1="12" x2="22" y2="12"/>
            <line x1="2"  y1="12" x2="9"  y2="12"/><line x1="2"  y1="15" x2="2"  y2="17"/>
            <line x1="5"  y1="15" x2="7"  y2="15"/>
          </svg>
        {/if}
      </button>
    </div>

    {#if suggestions.length > 0}
      <div class="suggestions">
        {#each suggestions as s}
          <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
          <div class="suggestion-row" on:click={() => pickSuggestion(s)}>
            <div class="sug-main">
              <span class="sug-name">{s.name}</span>
              {#if s.calories_per_100g}
                <span class="sug-cal">{s.calories_per_100g} ккал/100г</span>
              {/if}
            </div>
            {#if s.source === 'fatsecret'}
              <span class="sug-badge fs">FS</span>
            {/if}
          </div>
        {/each}
      </div>
    {/if}
  </div>

  <!-- Grams & calories -->
  <div class="form-row">
    <div class="form-field">
      <label class="form-label" for="food-grams">Граммы</label>
      <input id="food-grams" class="form-input" type="number" inputmode="decimal"
        placeholder="100" bind:value={formGrams} min="1" />
    </div>
    <div class="form-field">
      <label class="form-label" for="food-cal">Калории</label>
      <input id="food-cal" class="form-input" type="number" inputmode="decimal"
        placeholder="авто" bind:value={formCalories} min="0" />
    </div>
  </div>

  <!-- Macros -->
  <div class="form-row">
    <div class="form-field">
      <label class="form-label" for="food-p">Белки (г)</label>
      <input id="food-p" class="form-input" type="number" inputmode="decimal"
        placeholder="—" bind:value={formProtein} min="0" />
    </div>
    <div class="form-field">
      <label class="form-label" for="food-f">Жиры (г)</label>
      <input id="food-f" class="form-input" type="number" inputmode="decimal"
        placeholder="—" bind:value={formFat} min="0" />
    </div>
    <div class="form-field">
      <label class="form-label" for="food-c">Углев. (г)</label>
      <input id="food-c" class="form-input" type="number" inputmode="decimal"
        placeholder="—" bind:value={formCarbs} min="0" />
    </div>
  </div>

  <!-- Per-100g hint when item selected -->
  {#if pickedItem?.calories_per_100g}
    <p class="per100-hint">
      {pickedItem.calories_per_100g} ккал · {pickedItem.protein_per_100g ?? '?'}Б · {pickedItem.fat_per_100g ?? '?'}Ж · {pickedItem.carbs_per_100g ?? '?'}У — на 100г
    </p>
  {/if}

  <button
    class="save-btn"
    disabled={saving || !formName.trim() || !formGrams}
    on:click={saveEntry}
  >
    {saving ? 'Сохраняю…' : 'Сохранить'}
  </button>
</Modal>

<style>
  /* ── Date nav ── */
  .date-nav-btns { display: flex; gap: 0.25rem; margin-top: 0.125rem; }
  .nav-btn {
    width: 2rem; height: 2rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.5rem;
    color: var(--color-text); font-size: 1.125rem;
    cursor: pointer; display: flex; align-items: center; justify-content: center;
    -webkit-tap-highlight-color: transparent;
  }
  .nav-btn:disabled { opacity: 0.35; cursor: default; }

  /* ── Scanner overlay ── */
  .scanner-overlay {
    position: fixed; inset: 0; z-index: 9999;
    background: rgba(0,0,0,0.92);
    display: flex; align-items: center; justify-content: center;
  }
  .scanner-inner {
    width: min(90vw, 360px);
    display: flex; flex-direction: column; align-items: center; gap: 1.25rem;
  }
  .scanner-hint { color: white; font-size: 0.9375rem; margin: 0; }
  .scanner-video {
    width: 100%; aspect-ratio: 1;
    border-radius: 1rem; object-fit: cover; background: #000;
  }
  .scan-frame {
    position: absolute;
    width: min(72vw, 260px); aspect-ratio: 1;
    pointer-events: none;
  }
  .corner {
    position: absolute;
    width: 1.5rem; height: 1.5rem;
    border-color: white; border-style: solid;
  }
  .corner.tl { top: 0; left: 0;   border-width: 3px 0 0 3px; border-radius: 2px 0 0 0; }
  .corner.tr { top: 0; right: 0;  border-width: 3px 3px 0 0; border-radius: 0 2px 0 0; }
  .corner.bl { bottom: 0; left: 0;  border-width: 0 0 3px 3px; border-radius: 0 0 0 2px; }
  .corner.br { bottom: 0; right: 0; border-width: 0 3px 3px 0; border-radius: 0 0 2px 0; }
  .scan-line {
    position: absolute; left: 0; right: 0; height: 2px;
    background: linear-gradient(90deg, transparent, var(--color-accent), transparent);
    animation: scan 2s ease-in-out infinite;
  }
  @keyframes scan {
    0%, 100% { top: 10%; }
    50%       { top: 88%; }
  }
  .scanner-cancel {
    padding: 0.625rem 2rem;
    background: rgba(255,255,255,0.12);
    border: 1px solid rgba(255,255,255,0.3);
    border-radius: 2rem;
    color: white; font-size: 0.9375rem;
    cursor: pointer; -webkit-tap-highlight-color: transparent;
  }

  /* ── Summary card ── */
  .card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    padding: 0.875rem 1rem;
  }
  .summary-card { margin-bottom: 1.25rem; }
  .summary-row { display: flex; align-items: baseline; justify-content: space-between; margin-bottom: 0.625rem; }
  .summary-main { display: flex; align-items: baseline; gap: 0.375rem; }
  .cal-value { font-family: "JetBrains Mono", monospace; font-size: 1.75rem; color: var(--color-text); }
  .cal-goal  { font-size: 0.875rem; color: var(--color-muted); }
  .cal-pct   { font-family: "JetBrains Mono", monospace; font-size: 1rem; color: var(--color-accent); }

  .progress-track {
    height: 6px; background: var(--color-bg);
    border-radius: 3px; overflow: hidden; margin-bottom: 0.75rem;
  }
  .progress-fill {
    height: 100%; background: var(--color-accent);
    border-radius: 3px; transition: width 0.4s ease;
  }
  .macros-row { display: flex; gap: 0.5rem; }
  .macro-chip {
    flex: 1; background: var(--color-bg);
    border: 1px solid var(--color-border); border-radius: 0.75rem;
    padding: 0.375rem 0.5rem; display: flex; flex-direction: column; align-items: center; gap: 2px;
  }
  .macro-val { font-family: "JetBrains Mono", monospace; font-size: 0.9375rem; color: var(--color-text); }
  .macro-lbl { font-size: 0.625rem; color: var(--color-muted); text-transform: uppercase; letter-spacing: 0.05em; }

  /* ── Meals ── */
  .meal-section { margin-bottom: 1rem; }
  .meal-header {
    display: flex; align-items: center; gap: 0.375rem;
    font-size: 0.8125rem; font-weight: 500; color: var(--color-text);
    margin: 0 0 0.375rem 0.25rem;
  }
  .meal-icon { font-size: 1rem; }
  .meal-cal  { margin-left: auto; font-family: "JetBrains Mono", monospace; font-size: 0.75rem; color: var(--color-muted); }

  .entry-row {
    display: flex; align-items: center; gap: 0.5rem;
    padding: 0.5rem 0; border-bottom: 1px solid var(--color-border); transition: opacity 0.2s;
  }
  .entry-row:last-child { border-bottom: none; }
  .entry-row.fading { opacity: 0.4; }
  .entry-info { flex: 1; display: flex; flex-direction: column; gap: 1px; }
  .entry-name { font-size: 0.9375rem; color: var(--color-text); }
  .entry-meta { font-size: 0.75rem; color: var(--color-muted); }

  .del-btn {
    background: none; border: none; color: var(--color-muted);
    cursor: pointer; padding: 0.25rem; -webkit-tap-highlight-color: transparent;
    border-radius: 0.5rem; display: flex; align-items: center; justify-content: center;
    transition: color 0.15s;
  }
  .del-btn:active { color: #e53e3e; }

  /* ── Empty ── */
  .empty-state { display: flex; align-items: center; justify-content: center; padding: 2.5rem 0; }
  .empty-hint  { font-size: 0.875rem; color: var(--color-muted); margin: 0; text-align: center; }

  /* ── FAB ── */
  .fab {
    position: fixed;
    bottom: calc(4.5rem + env(safe-area-inset-bottom));
    right: 1.25rem;
    width: 3.25rem; height: 3.25rem; border-radius: 50%;
    background: var(--color-accent); color: white;
    border: none; font-size: 1.75rem; line-height: 1;
    cursor: pointer; box-shadow: 0 4px 16px rgba(0,0,0,0.18);
    display: flex; align-items: center; justify-content: center;
    -webkit-tap-highlight-color: transparent;
    transition: transform 0.15s, opacity 0.15s; z-index: 50;
  }
  .fab:active { transform: scale(0.92); opacity: 0.85; }

  /* ── Modal form ── */
  .form-field { margin-bottom: 1rem; position: relative; }
  .form-label {
    display: block; font-size: 0.75rem; color: var(--color-muted);
    margin-bottom: 0.375rem; text-transform: uppercase; letter-spacing: 0.05em;
  }
  .form-input {
    width: 100%; padding: 0.625rem 0.875rem;
    background: var(--color-bg); border: 1px solid var(--color-border);
    border-radius: 0.875rem; color: var(--color-text); font-size: 1rem;
    font-family: inherit; box-sizing: border-box; -webkit-appearance: none;
  }
  .form-input:focus { outline: none; border-color: var(--color-accent); }

  .form-row { display: flex; gap: 0.625rem; margin-bottom: 0; }
  .form-row .form-field { flex: 1; }

  /* ── Name input + scan button ── */
  .name-input-wrap { position: relative; display: flex; }
  .name-input { padding-right: 3rem; }
  .scan-btn {
    position: absolute; right: 0.625rem; top: 50%; transform: translateY(-50%);
    background: none; border: none; color: var(--color-muted);
    cursor: pointer; padding: 0.25rem; -webkit-tap-highlight-color: transparent;
    display: flex; align-items: center; justify-content: center;
    transition: color 0.15s;
  }
  .scan-btn:active { color: var(--color-accent); }
  .spin { display: inline-block; animation: spin 1s linear infinite; font-size: 1.1rem; }
  @keyframes spin { to { transform: rotate(360deg); } }

  /* ── Suggestions ── */
  .autocomplete-wrap { z-index: 10; }
  .suggestions {
    position: absolute; top: 100%; left: 0; right: 0;
    background: var(--color-card); border: 1px solid var(--color-border);
    border-radius: 0.875rem; box-shadow: 0 4px 20px rgba(0,0,0,0.1);
    z-index: 100; overflow: hidden; margin-top: 2px;
  }
  .suggestion-row {
    display: flex; align-items: center; justify-content: space-between;
    padding: 0.625rem 0.875rem; cursor: pointer;
    border-bottom: 1px solid var(--color-border);
    -webkit-tap-highlight-color: transparent;
  }
  .suggestion-row:last-child { border-bottom: none; }
  .suggestion-row:active { background: var(--color-bg); }

  .sug-main { display: flex; flex-direction: column; gap: 1px; }
  .sug-name { font-size: 0.9375rem; color: var(--color-text); }
  .sug-cal  { font-size: 0.75rem; color: var(--color-muted); }

  .sug-badge {
    font-size: 0.625rem; font-weight: 600;
    padding: 2px 5px; border-radius: 0.375rem;
    text-transform: uppercase; letter-spacing: 0.04em; flex-shrink: 0;
  }
  .sug-badge.fs { background: #e2f0ff; color: #2b6cb0; }

  /* ── Barcode banners ── */
  .barcode-banner {
    border-radius: 0.75rem; padding: 0.625rem 0.875rem;
    font-size: 0.875rem; margin-bottom: 0.75rem; text-align: center;
  }
  .barcode-banner.searching { background: var(--color-card); color: var(--color-muted); }
  .barcode-banner.found     { background: #f0fff4; color: #276749; }
  .barcode-banner.notfound  { background: #fff5f5; color: #9b2c2c; }

  /* ── Per-100g hint ── */
  .per100-hint {
    font-size: 0.75rem; color: var(--color-muted);
    margin: -0.5rem 0 0.75rem;
    padding: 0.375rem 0.625rem;
    background: var(--color-card);
    border-radius: 0.5rem;
    text-align: center;
  }

  /* ── Meal selector ── */
  .meal-selector { display: flex; flex-wrap: wrap; gap: 0.375rem; }
  .meal-sel-btn {
    padding: 0.375rem 0.75rem;
    background: var(--color-bg); border: 1px solid var(--color-border);
    border-radius: 2rem; color: var(--color-text); font-size: 0.8125rem;
    cursor: pointer; -webkit-tap-highlight-color: transparent; transition: all 0.15s;
  }
  .meal-sel-btn.active { background: var(--color-accent); border-color: var(--color-accent); color: white; }

  /* ── Save button ── */
  .save-btn {
    width: 100%; padding: 0.875rem;
    background: var(--color-accent); color: white;
    border: none; border-radius: 1rem; font-size: 1rem;
    font-family: inherit; cursor: pointer;
    -webkit-tap-highlight-color: transparent; margin-top: 0.5rem; transition: opacity 0.15s;
  }
  .save-btn:disabled { opacity: 0.5; cursor: default; }

  /* ── Skeleton ── */
  .skeleton-list { display: flex; flex-direction: column; gap: 0.75rem; }
  .skeleton-card {
    height: 5rem; border-radius: 1.25rem;
    background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover, var(--color-border)) 50%, var(--color-card) 75%);
    background-size: 200% 100%; animation: shimmer 1.4s infinite;
  }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }
</style>
