<script lang="ts">
  import { onMount, onDestroy, tick } from 'svelte'
  import { supabase, today } from '../lib/supabase'
  import { user } from '../stores/user'
  import { avatar, avatarSrc } from '../stores/avatar'
  import AddFood from '../components/food/AddFood.svelte'
  import type { FoodCandidate, RawFoodEntry } from '../lib/food-types'

  const FS_WORKER = import.meta.env.VITE_FATSECRET_WORKER_URL ?? ''

  // ── Types ─────────────────────────────────────────────────────────────────
  type FoodView = 'main' | 'add' | 'detail' | 'barcode'
  type MealId   = 'breakfast' | 'lunch' | 'dinner' | 'snack'

  interface NutritionEntry {
    id:        string
    date:      string
    meal:      MealId
    food_id:   string | null
    food_name: string
    amount:    number
    unit:      string
    state:     string | null
    calories:  number | null
    protein:   number | null
    fat:       number | null
    carbs:     number | null
    created_at: string
  }

  interface NutritionGoals {
    daily_calories:  number
    daily_protein_g: number
    daily_fat_g:     number
    daily_carbs_g:   number
  }

  interface WeekDay {
    date:       string
    label:      string
    hasEntries: boolean
    isToday:    boolean
    isFuture:   boolean
  }

  type RawEntry = RawFoodEntry

  // ── Dry ↔ cooked patterns ─────────────────────────────────────────────────
  const DRY_COOKED: Array<{re: RegExp; coeff: number; dry: string; cooked: string}> = [
    { re: /гречк/i,    coeff: 2.8, dry: 'сухая',  cooked: 'варёная'  },
    { re: /рис/i,      coeff: 2.8, dry: 'сухой',  cooked: 'варёный'  },
    { re: /макарон/i,  coeff: 2.5, dry: 'сухие',  cooked: 'варёные'  },
    { re: /спагет/i,   coeff: 2.5, dry: 'сухие',  cooked: 'варёные'  },
    { re: /вермишел/i, coeff: 2.5, dry: 'сухая',  cooked: 'варёная'  },
    { re: /паста/i,    coeff: 2.5, dry: 'сухая',  cooked: 'варёная'  },
    { re: /овсян/i,    coeff: 2.0, dry: 'сухая',  cooked: 'варёная'  },
    { re: /чечевиц/i,  coeff: 2.5, dry: 'сухая',  cooked: 'варёная'  },
    { re: /фасол/i,    coeff: 2.5, dry: 'сухая',  cooked: 'варёная'  },
    { re: /горо[хш]/i, coeff: 2.5, dry: 'сухой',  cooked: 'варёный'  },
    { re: /перловк/i,  coeff: 2.8, dry: 'сухая',  cooked: 'варёная'  },
    { re: /пшен/i,     coeff: 2.8, dry: 'сухое',  cooked: 'варёное'  },
  ]

  function getDryCooked(name: string) {
    return DRY_COOKED.find(p => p.re.test(name)) ?? null
  }

  // ── Meal config ───────────────────────────────────────────────────────────
  const MEALS: Array<{id: MealId; label: string; icon: string; color: string}> = [
    { id: 'breakfast', label: 'Завтрак', icon: '🌅', color: '#FF9500' },
    { id: 'lunch',     label: 'Обед',    icon: '☀️',  color: '#34C759' },
    { id: 'dinner',    label: 'Ужин',    icon: '🌆',  color: '#5E5CE6' },
    { id: 'snack',     label: 'Перекус', icon: '🌙',  color: '#FF3B30' },
  ]
  const DAY_NAMES = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']

  // ── Navigation ────────────────────────────────────────────────────────────
  let view: FoodView        = 'main'
  let selectedDate          = today()
  let showDatePicker        = false
  let expandedMeal: MealId | null = null
  let addingMeal: MealId    = 'breakfast'

  // ── Data ──────────────────────────────────────────────────────────────────
  let loading             = true
  let entries: NutritionEntry[] = []
  let goals: NutritionGoals = { daily_calories: 1600, daily_protein_g: 90, daily_fat_g: 55, daily_carbs_g: 180 }
  let weekDays: WeekDay[] = []
  let streak              = 0
  let recentEntries: RawEntry[]   = []
  let frequentEntries: RawEntry[] = []

  // ── Product detail ────────────────────────────────────────────────────────
  let detailFood: FoodCandidate | null = null
  let detailAmount: number | null      = 100
  let detailUnit                       = 'г'
  let detailStateCooked                = false   // false=dry/default, true=cooked
  let saving                           = false

  // ── Barcode scanner ───────────────────────────────────────────────────────
  let barcodeStatus = ''
  let scannerVideoEl: HTMLVideoElement | null = null
  let scannerControls: {stop: () => void} | null = null

  // ── Totals ────────────────────────────────────────────────────────────────
  $: totalCalories = entries.reduce((s, e) => s + (e.calories ?? 0), 0)
  $: totalProtein  = entries.reduce((s, e) => s + (e.protein  ?? 0), 0)
  $: totalFat      = entries.reduce((s, e) => s + (e.fat      ?? 0), 0)
  $: totalCarbs    = entries.reduce((s, e) => s + (e.carbs    ?? 0), 0)
  $: remaining     = goals.daily_calories - totalCalories
  $: calOver       = totalCalories > goals.daily_calories
  $: caloriesPct   = Math.min(100, Math.round(totalCalories / goals.daily_calories * 100))
  $: usedDots      = Math.min(100, Math.round(totalCalories / goals.daily_calories * 100))

  function mealItems(id: MealId) { return entries.filter(e => e.meal === id) }
  function mealCal(id: MealId)   { return mealItems(id).reduce((s, e) => s + (e.calories ?? 0), 0) }

  // ── Detail derived ────────────────────────────────────────────────────────
  $: detailDC    = detailFood ? getDryCooked(detailFood.name) : null
  $: stateCoeff  = (detailDC && detailStateCooked) ? detailDC.coeff : 1
  $: detailCal   = (detailFood?.calories_per_100g != null && detailAmount != null)
    ? Math.round(detailFood.calories_per_100g * detailAmount / 100 / stateCoeff) : null
  $: detailProt  = (detailFood?.protein_per_100g  != null && detailAmount != null)
    ? Math.round(detailFood.protein_per_100g  * detailAmount / 100 / stateCoeff * 10) / 10 : null
  $: detailFatV  = (detailFood?.fat_per_100g      != null && detailAmount != null)
    ? Math.round(detailFood.fat_per_100g      * detailAmount / 100 / stateCoeff * 10) / 10 : null
  $: detailCarb  = (detailFood?.carbs_per_100g    != null && detailAmount != null)
    ? Math.round(detailFood.carbs_per_100g    * detailAmount / 100 / stateCoeff * 10) / 10 : null

  // Percent of daily goal
  $: detailCalPct = detailCal != null
    ? Math.round(detailCal / goals.daily_calories * 100) : null

  // ── Helpers ───────────────────────────────────────────────────────────────
  function fmt(n: number | null): string {
    return n != null ? Math.round(n).toString() : '—'
  }
  function fmtD(n: number | null): string {
    return n != null ? (Math.round(n * 10) / 10).toString() : '—'
  }
  function mealLabel(id: MealId) { return MEALS.find(m => m.id === id)?.label ?? id }
  function mealIcon(id: MealId)  { return MEALS.find(m => m.id === id)?.icon  ?? '🍽️' }
  function mealColor(id: MealId) { return MEALS.find(m => m.id === id)?.color ?? '#8E8E93' }

  // Streak pluralisation
  function streakLabel(n: number): string {
    if (n % 10 === 1 && n % 100 !== 11) return 'день'
    if ([2,3,4].includes(n % 10) && ![12,13,14].includes(n % 100)) return 'дня'
    return 'дней'
  }

  // ── Date helpers ──────────────────────────────────────────────────────────
  function isToday(d: string)  { return d === today() }
  function isFuture(d: string) { return d > today() }

  function formatTitle(d: string): string {
    if (isToday(d)) return 'Сегодня'
    const dt   = new Date(d + 'T00:00:00')
    const diff = Math.round((new Date(today() + 'T00:00:00').getTime() - dt.getTime()) / 86400000)
    if (diff === 1) return 'Вчера'
    return dt.toLocaleDateString('ru', { weekday: 'long', day: 'numeric', month: 'long' })
  }

  function getWeekDates(date: string): string[] {
    const d   = new Date(date + 'T00:00:00')
    const dow = d.getDay()  // 0=Sun
    const mon = new Date(d)
    mon.setDate(d.getDate() - ((dow + 6) % 7))
    return Array.from({ length: 7 }, (_, i) => {
      const dd = new Date(mon)
      dd.setDate(mon.getDate() + i)
      return dd.toISOString().slice(0, 10)
    })
  }

  function prevDay() {
    const d = new Date(selectedDate + 'T00:00:00')
    d.setDate(d.getDate() - 1)
    selectedDate = d.toISOString().slice(0, 10)
  }
  function nextDay() {
    const d = new Date(selectedDate + 'T00:00:00')
    d.setDate(d.getDate() + 1)
    const nd = d.toISOString().slice(0, 10)
    if (nd <= today()) selectedDate = nd
  }

  function handleDateInput(e: Event) {
    const val = (e.target as HTMLInputElement).value
    if (val) { selectedDate = val; showDatePicker = false }
  }

  // ── Load ──────────────────────────────────────────────────────────────────
  async function load() {
    if (!$user) return
    loading = true

    const week      = getWeekDates(selectedDate)
    const weekStart = week[0]
    const weekEnd   = week[6]

    const [entRes, goalsRes, weekRes, histRes] = await Promise.all([
      supabase.from('nutrition_entries').select('*')
        .eq('user_id', $user.id).eq('date', selectedDate).order('created_at'),
      supabase.from('nutrition_goals').select('*')
        .eq('user_id', $user.id).single(),
      supabase.from('nutrition_entries').select('date')
        .eq('user_id', $user.id).gte('date', weekStart).lte('date', weekEnd),
      supabase.from('nutrition_entries')
        .select('food_name, amount, unit, calories, protein, fat, carbs')
        .eq('user_id', $user.id).order('created_at', { ascending: false }).limit(200),
    ])

    entries = entRes.data ?? []
    if (goalsRes.data) goals = goalsRes.data

    // Week strip
    const datesWithEntries = new Set((weekRes.data ?? []).map((r: {date: string}) => r.date))
    weekDays = week.map((d, i) => ({
      date: d, label: DAY_NAMES[i],
      hasEntries: datesWithEntries.has(d),
      isToday:    isToday(d),
      isFuture:   isFuture(d),
    }))

    // Streak: consecutive days backward from today
    const ago30 = new Date(today() + 'T00:00:00')
    ago30.setDate(ago30.getDate() - 30)
    const { data: streakData } = await supabase.from('nutrition_entries').select('date')
      .eq('user_id', $user.id)
      .gte('date', ago30.toISOString().slice(0, 10))
      .lte('date', today())
    const streakDates = new Set((streakData ?? []).map((r: {date: string}) => r.date))
    streak = 0
    const cur = new Date(today() + 'T00:00:00')
    while (streakDates.has(cur.toISOString().slice(0, 10))) {
      streak++
      cur.setDate(cur.getDate() - 1)
    }

    // Recent (newest unique)
    const hist         = histRes.data ?? []
    const seenR        = new Set<string>()
    recentEntries      = hist
      .filter((e: RawEntry) => { const k = e.food_name.toLowerCase(); if (seenR.has(k)) return false; seenR.add(k); return true })
      .slice(0, 20)

    // Frequent (by count)
    const freq: Record<string, {count: number; e: RawEntry}> = {}
    for (const e of hist) {
      const k = e.food_name.toLowerCase()
      if (!freq[k]) freq[k] = { count: 0, e }
      freq[k].count++
    }
    frequentEntries = Object.values(freq).sort((a, b) => b.count - a.count).slice(0, 20).map(f => f.e)

    loading = false
  }

  $: if (selectedDate && $user) load()

  // ── Entry actions ─────────────────────────────────────────────────────────
  let deletingId: string | null = null
  async function deleteEntry(id: string) {
    if (!$user) return
    deletingId = id
    await supabase.from('nutrition_entries').delete().eq('id', id).eq('user_id', $user.id)
    entries    = entries.filter(e => e.id !== id)
    deletingId = null
  }

  // ── Open add food screen ──────────────────────────────────────────────────
  function openAdd(meal: MealId) {
    addingMeal = meal
    view       = 'add'
  }

  // ── Food picked from AddFood ──────────────────────────────────────────────
  function onFoodPicked(e: CustomEvent<FoodCandidate>) {
    detailFood        = e.detail
    detailAmount      = 100
    detailUnit        = 'г'
    detailStateCooked = false
    view              = 'detail'
  }

  // ── Barcode scanner ───────────────────────────────────────────────────────
  async function openBarcode() {
    view          = 'barcode'
    barcodeStatus = ''
    await tick()
    await new Promise(r => setTimeout(r, 200))
    if (!scannerVideoEl) return
    try {
      const { BrowserMultiFormatReader } = await import('@zxing/browser')
      const reader = new BrowserMultiFormatReader()
      scannerControls = await reader.decodeFromVideoDevice(
        undefined, scannerVideoEl,
        (result, _err, controls) => {
          if (result) { controls.stop(); lookupBarcode(result.getText()) }
        }
      )
    } catch { barcodeStatus = 'error'; view = 'add' }
  }

  function stopScanner() {
    scannerControls?.stop()
    scannerControls = null
  }

  async function lookupBarcode(code: string) {
    barcodeStatus = 'searching'
    // 1) Open Food Facts
    try {
      const res  = await fetch(`https://world.openfoodfacts.org/api/v2/product/${code}.json`)
      const data = await res.json()
      if (data.status === 1 && data.product) {
        const p = data.product
        const n = p.nutriments ?? {}
        const nameFromEntries = (Object.entries(p as Record<string, unknown>)
          .find(([k, v]) => k.startsWith('product_name_') && typeof v === 'string' && (v as string).length > 0)
          ?.[1] ?? '') as string
        const name =
          (p.product_name_ru as string | undefined) ||
          (p.product_name_en as string | undefined) ||
          (p.product_name    as string | undefined) ||
          (p.product_name_de as string | undefined) ||
          (p.product_name_fr as string | undefined) ||
          nameFromEntries || ''
        if (name) {
          let kcal: number | null = null
          if      (n['energy-kcal_100g'] != null) kcal = Math.round(n['energy-kcal_100g'])
          else if (n['energy_100g']      != null) kcal = Math.round(n['energy_100g'] / 4.184)
          detailFood = {
            id:                `off-${code}`,
            name,
            brand:             (p.brands as string | undefined) ?? null,
            calories_per_100g: kcal,
            protein_per_100g:  n.proteins_100g     != null ? Math.round(n.proteins_100g     * 10) / 10 : null,
            fat_per_100g:      n.fat_100g           != null ? Math.round(n.fat_100g           * 10) / 10 : null,
            carbs_per_100g:    n.carbohydrates_100g != null ? Math.round(n.carbohydrates_100g * 10) / 10 : null,
            source:            'local',
          }
          detailAmount = 100; detailUnit = 'г'; detailStateCooked = false
          barcodeStatus = 'found'; view = 'detail'; return
        }
      }
    } catch { /* fall through */ }

    // 2) FatSecret Worker fallback
    if (FS_WORKER) {
      try {
        const res  = await fetch(`${FS_WORKER}/barcode?code=${encodeURIComponent(code)}`)
        const data = await res.json()
        if (data.found) {
          detailFood = {
            id:                `fs-${data.id}`,
            name:              data.name,
            brand:             data.brand ?? null,
            calories_per_100g: data.calories_per_100g ?? null,
            protein_per_100g:  data.protein_per_100g  ?? null,
            fat_per_100g:      data.fat_per_100g      ?? null,
            carbs_per_100g:    data.carbs_per_100g    ?? null,
            source:            'fatsecret',
          }
          detailAmount = 100; detailUnit = 'г'; detailStateCooked = false
          barcodeStatus = 'found'; view = 'detail'; return
        }
      } catch { /* ignore */ }
    }

    barcodeStatus = 'notfound'
    view = 'add'
  }

  // ── Save entry ────────────────────────────────────────────────────────────
  async function saveEntry() {
    if (!$user || !detailFood || !detailAmount) return
    saving = true
    try {
      // Cache FatSecret food in nutrition_foods
      let foodId: string | null = null
      if (detailFood.id.startsWith('fs-')) {
        const fsId = detailFood.id.slice(3)
        const { data: existing } = await supabase.from('nutrition_foods')
          .select('id').eq('fatsecret_id', fsId).maybeSingle()
        if (existing) {
          foodId = existing.id
        } else {
          const { data: newF } = await supabase.from('nutrition_foods').insert({
            fatsecret_id:      fsId,
            name:              detailFood.name,
            brand:             detailFood.brand,
            calories_per_100g: detailFood.calories_per_100g,
            protein_per_100g:  detailFood.protein_per_100g,
            fat_per_100g:      detailFood.fat_per_100g,
            carbs_per_100g:    detailFood.carbs_per_100g,
          }).select('id').single()
          if (newF) foodId = newF.id
        }
      }

      const stateName = detailDC
        ? (detailStateCooked ? detailDC.cooked : detailDC.dry)
        : null

      const { data } = await supabase.from('nutrition_entries').insert({
        user_id:   $user.id,
        date:      selectedDate,
        meal:      addingMeal,
        food_id:   foodId,
        food_name: detailFood.name,
        amount:    detailAmount,
        unit:      detailUnit,
        state:     stateName,
        calories:  detailCal,
        protein:   detailProt,
        fat:       detailFatV,
        carbs:     detailCarb,
      }).select().single()

      if (data) {
        entries    = [...entries, data]
        detailFood = null
        view       = 'main'
      }
    } finally { saving = false }
  }

  onMount(load)
  onDestroy(stopScanner)
</script>

<!-- ── Barcode scanner overlay ──────────────────────────────────────────────── -->
{#if view === 'barcode'}
  <div class="scanner-overlay">
    <div class="scanner-inner">
      <p class="scanner-hint">Наведи камеру на штрихкод</p>
      {#if barcodeStatus === 'searching'}
        <p class="scanner-status">🔍 Ищу продукт…</p>
      {:else if barcodeStatus === 'error'}
        <p class="scanner-status err">Ошибка камеры</p>
      {:else}
        <p class="scanner-tip">Настройки → Safari → Камера → Разрешить</p>
      {/if}
      <!-- svelte-ignore a11y-media-has-caption -->
      <video bind:this={scannerVideoEl} class="scanner-video" autoplay playsinline muted />
      <div class="scan-frame">
        <span class="corner tl"/><span class="corner tr"/>
        <span class="corner bl"/><span class="corner br"/>
        <div class="scan-line"/>
      </div>
      <button class="scanner-cancel" on:click={() => { stopScanner(); view = 'add' }}>Отмена</button>
    </div>
  </div>
{/if}

<!-- ── Add food screen ──────────────────────────────────────────────────────── -->
{#if view === 'add'}
  <AddFood
    mealLabel={MEALS.find(m => m.id === addingMeal)?.label ?? 'приём пищи'}
    {recentEntries}
    {frequentEntries}
    fsWorker={FS_WORKER}
    on:pick={onFoodPicked}
    on:barcode={openBarcode}
    on:close={() => view = 'main'}
  />
{/if}

<!-- ── Product detail screen ─────────────────────────────────────────────────── -->
{#if view === 'detail' && detailFood}
  <div class="detail-screen">
    <header class="detail-header">
      <button class="detail-back" on:click={() => view = 'add'}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" width="20" height="20">
          <path d="M15 18l-6-6 6-6"/>
        </svg>
      </button>
      <div class="detail-title-block">
        {#if detailFood.brand}
          <span class="detail-brand">{detailFood.brand}</span>
        {/if}
        <span class="detail-food-name">{detailFood.name}</span>
      </div>
    </header>

    <div class="detail-scroll">
      <!-- Source badge -->
      {#if detailFood.source === 'fatsecret'}
        <div class="source-row">
          <span class="source-badge fs">FatSecret</span>
        </div>
      {/if}
      {#if barcodeStatus === 'found'}
        <div class="source-row">
          <span class="source-badge found">✓ Найдено по штрихкоду</span>
        </div>
      {/if}

      <!-- ── "Добавить в дневник" section ── -->
      <div class="card detail-card">
        <p class="detail-section-label">Добавить в дневник — {mealLabel(addingMeal)}</p>

        <!-- Amount + unit row -->
        <div class="amount-row">
          <div class="amount-stepper">
            <button class="step-btn" on:click={() => { if (detailAmount && detailAmount > 10) detailAmount -= 10 }}>−</button>
            <input
              class="amount-input"
              type="number"
              inputmode="decimal"
              bind:value={detailAmount}
              min="1"
            />
            <button class="step-btn" on:click={() => { detailAmount = (detailAmount ?? 0) + 10 }}>+</button>
          </div>
          <div class="unit-picker">
            {#each ['г', 'мл', 'шт'] as u}
              <button class="unit-btn" class:active={detailUnit === u}
                on:click={() => detailUnit = u}>{u}</button>
            {/each}
          </div>
        </div>

        <!-- Dry ↔ cooked toggle -->
        {#if detailDC}
          <div class="state-toggle">
            <button class="state-btn" class:active={!detailStateCooked}
              on:click={() => detailStateCooked = false}>
              {detailDC.dry}
            </button>
            <button class="state-btn" class:active={detailStateCooked}
              on:click={() => detailStateCooked = true}>
              {detailDC.cooked} ×{detailDC.coeff}
            </button>
          </div>
          {#if detailStateCooked}
            <p class="coeff-hint">
              {detailAmount ?? 100}г {detailDC.cooked} = {Math.round((detailAmount ?? 100) / detailDC.coeff)}г {detailDC.dry}
            </p>
          {/if}
        {/if}

        <!-- Macro grid -->
        <div class="macro-grid">
          <div class="macro-cell cal">
            <span class="macro-cell-val">{fmt(detailCal)}</span>
            <span class="macro-cell-lbl">ккал</span>
            {#if detailCalPct != null}
              <span class="macro-cell-pct">{detailCalPct}% РСК</span>
            {/if}
          </div>
          <div class="macro-cell">
            <span class="macro-cell-val">{fmtD(detailProt)}</span>
            <span class="macro-cell-lbl">Белки (г)</span>
          </div>
          <div class="macro-cell">
            <span class="macro-cell-val">{fmtD(detailFatV)}</span>
            <span class="macro-cell-lbl">Жиры (г)</span>
          </div>
          <div class="macro-cell">
            <span class="macro-cell-val">{fmtD(detailCarb)}</span>
            <span class="macro-cell-lbl">Углев. (г)</span>
          </div>
        </div>

        <!-- Per-100g reference -->
        {#if detailFood.calories_per_100g}
          <p class="per100g">
            На 100г: {detailFood.calories_per_100g} ккал ·
            {detailFood.protein_per_100g ?? '?'}Б ·
            {detailFood.fat_per_100g     ?? '?'}Ж ·
            {detailFood.carbs_per_100g   ?? '?'}У
          </p>
        {/if}

        <button class="save-btn" disabled={saving || !detailAmount} on:click={saveEntry}>
          {saving ? 'Сохраняю…' : 'Сохранить'}
        </button>
      </div>

      <div class="bottom-spacer" />
    </div>
  </div>
{/if}

<!-- ── Main diary view ─────────────────────────────────────────────────────── -->
<div class="food-page" class:hidden={view !== 'main'}>

  <!-- Header -->
  <header class="food-header">
    <button class="bell-btn" aria-label="Уведомления">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" width="22" height="22">
        <path d="M18 8a6 6 0 00-12 0c0 7-3 9-3 9h18s-3-2-3-9"/>
        <path d="M13.73 21a2 2 0 01-3.46 0"/>
      </svg>
    </button>

    <div class="header-pill">
      <button class="pill-btn" on:click={() => openAdd('lunch')} aria-label="Поиск">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="15" height="15">
          <circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>
        </svg>
        <span>Поиск</span>
      </button>
      <div class="pill-divider" />
      <button class="pill-btn" on:click={() => showDatePicker = !showDatePicker} aria-label="Выбор даты">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="15" height="15">
          <rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/>
          <line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/>
        </svg>
        <span>Дата</span>
      </button>
    </div>

    <img src={avatarSrc($avatar, 192)} alt="аватар" class="header-avatar" />
  </header>

  <!-- Hidden date picker -->
  {#if showDatePicker}
    <div class="date-picker-row">
      <input type="date" class="date-input" value={selectedDate} max={today()} on:change={handleDateInput} />
    </div>
  {/if}

  <div class="food-scroll">

    <!-- Title + day nav -->
    <div class="day-title-row">
      <button class="nav-arrow" on:click={prevDay}>‹</button>
      <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
      <h1 class="day-title" on:click={() => showDatePicker = !showDatePicker}>
        {formatTitle(selectedDate)}
      </h1>
      <button class="nav-arrow" on:click={nextDay} disabled={isToday(selectedDate)}>›</button>
    </div>

    {#if loading}
      <!-- Skeleton -->
      <div class="skeleton-stack">
        {#each [1,2,3,4] as _}<div class="skeleton-card" />{/each}
      </div>
    {:else}

      <!-- ── 7-day strip ── -->
      <div class="card week-card">
        {#if streak > 0}
          <p class="streak-label">🔥 {streak} {streakLabel(streak)}</p>
        {/if}
        <div class="week-strip">
          {#each weekDays as d}
            <button
              class="day-circle"
              class:has-entries={d.hasEntries}
              class:is-today={d.isToday && !d.hasEntries}
              class:is-future={d.isFuture}
              class:is-selected={d.date === selectedDate}
              disabled={d.isFuture}
              on:click={() => selectedDate = d.date}
            >
              <span class="day-lbl">{d.label}</span>
              {#if d.hasEntries}
                <span class="day-check">✓</span>
              {:else}
                <span class="day-dot" />
              {/if}
            </button>
          {/each}
        </div>
      </div>

      <!-- ── Calorie card ── -->
      <div class="card calorie-card">
        <div class="calorie-top">
          <div class="calorie-left">
            <span class="calorie-label">КАЛОРИИ</span>
            <div class="calorie-numbers">
              <span class="calorie-eaten">{fmt(totalCalories)}</span>
              <span class="calorie-goal">/ {goals.daily_calories}</span>
            </div>
          </div>
          <div class="calorie-right">
            <span class="remaining-label">{calOver ? 'ПЕРЕБОР' : 'ОСТАЛОСЬ'}</span>
            <span class="remaining-val" class:over={calOver}>
              {calOver ? `+${fmt(totalCalories - goals.daily_calories)}` : fmt(remaining)}
            </span>
          </div>
        </div>

        <div class="progress-track">
          <div class="progress-fill" class:over={calOver} style="width: {caloriesPct}%" />
        </div>

        <div class="macro-bar">
          <div class="macro-bar-item">
            <span class="mb-val">{fmt(totalProtein)}г</span>
            <span class="mb-lbl">Белки</span>
            <div class="mb-track">
              <div class="mb-fill prot" style="width: {Math.min(100, totalProtein / goals.daily_protein_g * 100)}%" />
            </div>
          </div>
          <div class="macro-bar-item">
            <span class="mb-val">{fmt(totalFat)}г</span>
            <span class="mb-lbl">Жиры</span>
            <div class="mb-track">
              <div class="mb-fill fat" style="width: {Math.min(100, totalFat / goals.daily_fat_g * 100)}%" />
            </div>
          </div>
          <div class="macro-bar-item">
            <span class="mb-val">{fmt(totalCarbs)}г</span>
            <span class="mb-lbl">Углев.</span>
            <div class="mb-track">
              <div class="mb-fill carb" style="width: {Math.min(100, totalCarbs / goals.daily_carbs_g * 100)}%" />
            </div>
          </div>
        </div>
      </div>

      <!-- ── Meal cards ── -->
      {#each MEALS as meal}
        {@const items = mealItems(meal.id)}
        <div class="card meal-card">
          <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
          <div class="meal-row" on:click={() => expandedMeal = expandedMeal === meal.id ? null : meal.id}>
            <div class="meal-icon-wrap" style="background: {meal.color}22">
              <span class="meal-ico">{meal.icon}</span>
            </div>
            <div class="meal-info">
              <span class="meal-name">{meal.label}</span>
              <span class="meal-sub">
                {#if items.length === 0}
                  Нет записей
                {:else}
                  {items.length} {items.length === 1 ? 'продукт' : items.length < 5 ? 'продукта' : 'продуктов'} · {fmt(mealCal(meal.id))} ккал
                {/if}
              </span>
            </div>
            <button
              class="add-btn"
              style="background: {meal.color}"
              on:click|stopPropagation={() => openAdd(meal.id)}
              aria-label="Добавить в {meal.label}"
            >+</button>
          </div>

          {#if expandedMeal === meal.id}
            <div class="meal-entries">
              {#if items.length === 0}
                <p class="entries-empty">Нет записей — нажмите + чтобы добавить</p>
              {:else}
                {#each items as entry}
                  <div class="entry-row" class:fading={deletingId === entry.id}>
                    <div class="entry-info">
                      <span class="entry-name">{entry.food_name}</span>
                      <span class="entry-meta">
                        {entry.amount}{entry.unit}
                        {#if entry.state} · {entry.state}{/if}
                        {#if entry.calories != null} · {fmt(entry.calories)} ккал{/if}
                      </span>
                    </div>
                    <button class="del-btn" on:click={() => deleteEntry(entry.id)} aria-label="Удалить">
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" width="15" height="15">
                        <polyline points="3 6 5 6 21 6"/>
                        <path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/>
                        <path d="M10 11v6M14 11v6M9 6V4a1 1 0 011-1h4a1 1 0 011 1v2"/>
                      </svg>
                    </button>
                  </div>
                {/each}
              {/if}
            </div>
          {/if}
        </div>
      {/each}

      <!-- ── Day summary ── -->
      <div class="card summary-card">
        <p class="summary-title">Итог дня</p>
        <div class="summary-body">
          <div class="summary-table">
            <div class="st-row">
              <span class="st-lbl">Употреблено</span>
              <span class="st-val">{fmt(totalCalories)} ккал</span>
            </div>
            <div class="st-row">
              <span class="st-lbl">Сожжено</span>
              <span class="st-val muted">— ккал</span>
            </div>
            <div class="st-row">
              <span class="st-lbl">Осталось</span>
              <span class="st-val" class:green={!calOver} class:orange={calOver}>
                {calOver ? `−${fmt(totalCalories - goals.daily_calories)}` : fmt(remaining)} ккал
              </span>
            </div>
          </div>

          <!-- 10×10 dot grid -->
          <div class="dot-grid" aria-label="Визуализация калорий">
            {#each Array(100) as _, i}
              <div class="dot"
                class:dot-used={i < usedDots}
                class:dot-over={calOver && i < usedDots}
              />
            {/each}
          </div>
        </div>
      </div>

      <div class="bottom-spacer" />
    {/if}
  </div>
</div>

<style>
  /* ── Page shell ── */
  .food-page {
    position: relative;
    max-width: 480px;
    margin: 0 auto;
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
  }
  .food-page.hidden { display: none; }

  /* ── Header ── */
  .food-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.75rem 1.125rem 0.625rem;
    padding-top: calc(0.75rem + env(safe-area-inset-top));
    position: sticky;
    top: 0;
    background: var(--color-bg);
    z-index: 10;
    flex-shrink: 0;
  }
  .bell-btn {
    width: 2.375rem; height: 2.375rem; border-radius: 50%;
    background: var(--color-card); border: 1px solid var(--color-border);
    color: var(--color-muted); cursor: pointer; display: flex; align-items: center; justify-content: center;
    -webkit-tap-highlight-color: transparent;
    flex-shrink: 0;
  }
  .header-pill {
    display: flex; align-items: center;
    background: var(--color-card); border: 1px solid var(--color-border);
    border-radius: 2rem; overflow: hidden;
  }
  .pill-btn {
    display: flex; align-items: center; gap: 0.3rem;
    padding: 0.4rem 0.875rem;
    background: none; border: none;
    color: var(--color-muted); font-size: 0.8125rem; font-family: inherit;
    cursor: pointer; -webkit-tap-highlight-color: transparent;
    transition: color 0.15s;
  }
  .pill-btn:active { color: var(--color-accent); }
  .pill-divider { width: 1px; height: 1.25rem; background: var(--color-border); }
  .header-avatar {
    width: 2.375rem; height: 2.375rem; border-radius: 0.625rem;
    object-fit: cover; flex-shrink: 0;
  }

  /* ── Date picker ── */
  .date-picker-row {
    padding: 0.375rem 1.125rem 0.25rem;
    display: flex; justify-content: center;
  }
  .date-input {
    background: var(--color-card); border: 1px solid var(--color-border);
    border-radius: 0.75rem; padding: 0.5rem 0.875rem;
    color: var(--color-text); font-size: 0.9375rem; font-family: inherit;
    outline: none; -webkit-appearance: none;
  }

  /* ── Scroll container ── */
  .food-scroll {
    flex: 1; overflow-y: auto;
    padding: 0 1.125rem 0.5rem;
    -webkit-overflow-scrolling: touch;
  }

  /* ── Day title ── */
  .day-title-row {
    display: flex; align-items: center; gap: 0.375rem;
    padding: 0.375rem 0 0.75rem;
  }
  .day-title {
    flex: 1; margin: 0;
    font-size: 1.625rem; font-weight: 700; color: var(--color-text);
    text-align: center; cursor: pointer;
    -webkit-tap-highlight-color: transparent;
  }
  .nav-arrow {
    width: 2rem; height: 2rem; border-radius: 50%;
    background: var(--color-card); border: 1px solid var(--color-border);
    color: var(--color-text); font-size: 1.25rem; line-height: 1;
    cursor: pointer; display: flex; align-items: center; justify-content: center;
    -webkit-tap-highlight-color: transparent; flex-shrink: 0;
  }
  .nav-arrow:disabled { opacity: 0.35; cursor: default; }

  /* ── Card base ── */
  .card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.125rem;
    padding: 1rem 1rem;
    margin-bottom: 0.875rem;
  }

  /* ── Week card ── */
  .week-card { padding: 0.75rem 0.75rem; }
  .streak-label {
    font-size: 0.8rem; color: var(--color-muted); margin: 0 0 0.5rem;
    font-weight: 500; letter-spacing: 0.02em;
  }
  .week-strip { display: flex; justify-content: space-between; gap: 0.25rem; }
  .day-circle {
    flex: 1; display: flex; flex-direction: column; align-items: center; gap: 0.2rem;
    padding: 0.375rem 0.125rem; border-radius: 0.75rem;
    background: none; border: 1px solid transparent;
    cursor: pointer; -webkit-tap-highlight-color: transparent; transition: all 0.15s;
  }
  .day-circle:disabled { cursor: default; opacity: 0.45; }
  .day-circle.is-selected {
    background: var(--color-accent)15;
    border-color: var(--color-accent)40;
  }
  .day-lbl  { font-size: 0.65rem; color: var(--color-muted); font-weight: 500; text-transform: uppercase; }
  .day-check {
    width: 1.5rem; height: 1.5rem; border-radius: 50%;
    background: var(--color-success);
    color: white; font-size: 0.625rem;
    display: flex; align-items: center; justify-content: center; font-weight: 700;
  }
  .day-circle.is-today .day-dot {
    width: 1.5rem; height: 1.5rem; border-radius: 50%;
    border: 2px dashed var(--color-accent);
    background: none;
  }
  .day-dot {
    width: 1.5rem; height: 1.5rem; border-radius: 50%;
    border: 1.5px dashed var(--color-border);
  }

  /* ── Calorie card ── */
  .calorie-card { }
  .calorie-top { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 0.75rem; }
  .calorie-left, .calorie-right { display: flex; flex-direction: column; gap: 2px; }
  .calorie-right { align-items: flex-end; }
  .calorie-label   { font-size: 0.625rem; font-weight: 700; color: var(--color-muted); letter-spacing: 0.08em; text-transform: uppercase; }
  .remaining-label { font-size: 0.625rem; font-weight: 700; color: var(--color-muted); letter-spacing: 0.08em; text-transform: uppercase; }
  .calorie-numbers { display: flex; align-items: baseline; gap: 0.25rem; }
  .calorie-eaten   { font-size: 2.25rem; font-weight: 700; color: var(--color-text); font-family: "JetBrains Mono", monospace; line-height: 1; }
  .calorie-goal    { font-size: 0.875rem; color: var(--color-muted); }
  .remaining-val   { font-size: 1.75rem; font-weight: 700; color: var(--color-success); font-family: "JetBrains Mono", monospace; line-height: 1; }
  .remaining-val.over { color: var(--color-warning); }

  .progress-track { height: 6px; background: var(--color-bg); border-radius: 3px; overflow: hidden; margin-bottom: 0.875rem; }
  .progress-fill  { height: 100%; background: var(--color-success); border-radius: 3px; transition: width 0.5s ease; }
  .progress-fill.over { background: var(--color-warning); }

  .macro-bar { display: flex; gap: 0.625rem; }
  .macro-bar-item { flex: 1; display: flex; flex-direction: column; gap: 3px; }
  .mb-val   { font-size: 0.9rem; font-weight: 600; color: var(--color-text); font-family: "JetBrains Mono", monospace; }
  .mb-lbl   { font-size: 0.65rem; color: var(--color-muted); }
  .mb-track { height: 3px; background: var(--color-bg); border-radius: 2px; overflow: hidden; }
  .mb-fill  { height: 100%; border-radius: 2px; transition: width 0.5s ease; }
  .mb-fill.prot { background: #007AFF; }
  .mb-fill.fat  { background: #FF9500; }
  .mb-fill.carb { background: #FF3B30; }

  /* ── Meal cards ── */
  .meal-card { padding: 0; overflow: hidden; }
  .meal-row {
    display: flex; align-items: center; gap: 0.75rem;
    padding: 0.875rem 1rem; cursor: pointer;
    -webkit-tap-highlight-color: transparent;
  }
  .meal-icon-wrap {
    width: 2.75rem; height: 2.75rem; border-radius: 0.875rem;
    display: flex; align-items: center; justify-content: center; flex-shrink: 0;
  }
  .meal-ico  { font-size: 1.375rem; }
  .meal-info { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .meal-name { font-size: 1rem; font-weight: 600; color: var(--color-text); }
  .meal-sub  { font-size: 0.78rem; color: var(--color-muted); }
  .add-btn {
    width: 2.25rem; height: 2.25rem; border-radius: 50%;
    border: none; color: white; font-size: 1.5rem; line-height: 1;
    display: flex; align-items: center; justify-content: center;
    cursor: pointer; flex-shrink: 0; -webkit-tap-highlight-color: transparent;
    transition: transform 0.1s;
  }
  .add-btn:active { transform: scale(0.9); }

  .meal-entries { border-top: 1px solid var(--color-border); padding: 0.375rem 0; }
  .entries-empty { font-size: 0.8125rem; color: var(--color-muted); margin: 0.5rem 1rem; }

  .entry-row {
    display: flex; align-items: center; gap: 0.5rem;
    padding: 0.5rem 1rem; border-bottom: 1px solid var(--color-border);
    transition: opacity 0.2s;
  }
  .entry-row:last-child { border-bottom: none; }
  .entry-row.fading { opacity: 0.4; }
  .entry-info { flex: 1; display: flex; flex-direction: column; gap: 1px; min-width: 0; }
  .entry-name { font-size: 0.9rem; color: var(--color-text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .entry-meta { font-size: 0.72rem; color: var(--color-muted); }
  .del-btn {
    background: none; border: none; color: var(--color-muted); cursor: pointer;
    padding: 0.25rem; border-radius: 0.375rem;
    -webkit-tap-highlight-color: transparent; transition: color 0.15s;
    flex-shrink: 0;
  }
  .del-btn:active { color: var(--color-danger); }

  /* ── Summary card ── */
  .summary-title { font-size: 0.875rem; font-weight: 600; color: var(--color-text); margin: 0 0 0.75rem; }
  .summary-body  { display: flex; gap: 1rem; align-items: flex-start; }
  .summary-table { flex: 1; display: flex; flex-direction: column; gap: 0.5rem; }
  .st-row  { display: flex; justify-content: space-between; align-items: center; }
  .st-lbl  { font-size: 0.8125rem; color: var(--color-muted); }
  .st-val  { font-size: 0.875rem; font-weight: 600; color: var(--color-text); font-family: "JetBrains Mono", monospace; }
  .st-val.muted  { color: var(--color-muted); font-weight: 400; }
  .st-val.green  { color: var(--color-success); }
  .st-val.orange { color: var(--color-warning); }

  /* 10×10 dot grid */
  .dot-grid {
    display: grid; grid-template-columns: repeat(10, 1fr); gap: 3px;
    width: 120px; flex-shrink: 0;
  }
  .dot {
    aspect-ratio: 1; border-radius: 50%;
    background: var(--color-border);
  }
  .dot-used { background: var(--color-success); }
  .dot-over { background: var(--color-warning); }

  /* ── Skeleton ── */
  .skeleton-stack { display: flex; flex-direction: column; gap: 0.875rem; }
  .skeleton-card {
    height: 5.5rem; border-radius: 1.125rem;
    background: linear-gradient(90deg, var(--color-card) 25%, var(--color-border) 50%, var(--color-card) 75%);
    background-size: 200% 100%; animation: shimmer 1.4s infinite;
  }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  /* ── Scanner overlay ── */
  .scanner-overlay {
    position: fixed; inset: 0; z-index: 9999;
    background: rgba(0,0,0,0.92);
    display: flex; align-items: center; justify-content: center;
  }
  .scanner-inner  { width: min(90vw, 360px); display: flex; flex-direction: column; align-items: center; gap: 1.25rem; }
  .scanner-hint   { color: white; font-size: 0.9375rem; margin: 0; text-align: center; }
  .scanner-tip    { color: rgba(255,255,255,0.45); font-size: 0.72rem; margin: 0; text-align: center; line-height: 1.4; }
  .scanner-status { color: rgba(255,255,255,0.8); font-size: 0.875rem; margin: 0; }
  .scanner-status.err { color: #FF453A; }
  .scanner-video  { width: 100%; aspect-ratio: 1; border-radius: 1rem; object-fit: cover; background: #000; }
  .scan-frame {
    position: absolute;
    width: min(72vw, 260px); aspect-ratio: 1;
    pointer-events: none;
  }
  .corner { position: absolute; width: 1.5rem; height: 1.5rem; border-color: white; border-style: solid; }
  .corner.tl { top:0;    left:0;  border-width: 3px 0 0 3px; border-radius: 2px 0 0 0; }
  .corner.tr { top:0;    right:0; border-width: 3px 3px 0 0; border-radius: 0 2px 0 0; }
  .corner.bl { bottom:0; left:0;  border-width: 0 0 3px 3px; border-radius: 0 0 0 2px; }
  .corner.br { bottom:0; right:0; border-width: 0 3px 3px 0; border-radius: 0 0 2px 0; }
  .scan-line {
    position: absolute; left:0; right:0; height: 2px;
    background: linear-gradient(90deg, transparent, #FF3B30, transparent);
    animation: scan 2s ease-in-out infinite;
  }
  @keyframes scan { 0%,100% { top:10%; } 50% { top:88%; } }
  .scanner-cancel {
    padding: 0.625rem 2rem;
    background: rgba(255,255,255,0.12); border: 1px solid rgba(255,255,255,0.3);
    border-radius: 2rem; color: white; font-size: 0.9375rem; cursor: pointer;
    -webkit-tap-highlight-color: transparent;
  }

  /* ── Product detail screen ── */
  .detail-screen {
    position: fixed; inset: 0;
    background: var(--color-bg); z-index: 300;
    display: flex; flex-direction: column;
    animation: slideUp 0.28s cubic-bezier(0.32, 0.72, 0, 1);
  }
  @keyframes slideUp { from { transform: translateY(100%); } to { transform: translateY(0); } }

  .detail-header {
    display: flex; align-items: center; gap: 0.625rem;
    padding: 0.875rem 1rem 0.75rem;
    padding-top: calc(0.875rem + env(safe-area-inset-top));
    background: var(--color-card);
    border-bottom: 1px solid var(--color-border);
    flex-shrink: 0;
  }
  .detail-back {
    background: none; border: none; color: var(--color-accent);
    cursor: pointer; padding: 0.25rem; -webkit-tap-highlight-color: transparent;
    flex-shrink: 0;
  }
  .detail-title-block { flex: 1; display: flex; flex-direction: column; gap: 1px; min-width: 0; }
  .detail-brand     { font-size: 0.72rem; color: var(--color-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .detail-food-name { font-size: 1rem; font-weight: 600; color: var(--color-text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

  .detail-scroll {
    flex: 1; overflow-y: auto;
    padding: 0.875rem 1.125rem;
    -webkit-overflow-scrolling: touch;
  }

  .source-row { margin-bottom: 0.625rem; }
  .source-badge {
    display: inline-block; font-size: 0.75rem; font-weight: 600;
    padding: 3px 8px; border-radius: 6px;
  }
  .source-badge.fs    { background: #dbeafe; color: #1d4ed8; }
  .source-badge.found { background: #dcfce7; color: #166534; }

  .detail-card  { }
  .detail-section-label {
    font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.06em;
    color: var(--color-muted); margin: 0 0 0.875rem;
  }

  /* Amount row */
  .amount-row { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.875rem; }
  .amount-stepper {
    display: flex; align-items: center;
    background: var(--color-bg); border: 1px solid var(--color-border);
    border-radius: 0.875rem; overflow: hidden;
  }
  .step-btn {
    width: 2.5rem; height: 2.75rem;
    background: none; border: none; font-size: 1.25rem;
    color: var(--color-accent); cursor: pointer; -webkit-tap-highlight-color: transparent;
    transition: background 0.1s;
  }
  .step-btn:active { background: var(--color-border); }
  .amount-input {
    width: 5rem; text-align: center;
    background: none; border: none; border-left: 1px solid var(--color-border); border-right: 1px solid var(--color-border);
    color: var(--color-text); font-size: 1.125rem; font-weight: 600; font-family: inherit;
    padding: 0.5rem 0; outline: none; -webkit-appearance: none;
  }
  .unit-picker { display: flex; gap: 0.25rem; }
  .unit-btn {
    padding: 0.375rem 0.75rem;
    background: var(--color-bg); border: 1px solid var(--color-border); border-radius: 2rem;
    color: var(--color-muted); font-size: 0.875rem; font-family: inherit;
    cursor: pointer; -webkit-tap-highlight-color: transparent; transition: all 0.15s;
  }
  .unit-btn.active {
    background: var(--color-accent); border-color: var(--color-accent); color: white;
  }

  /* Dry ↔ cooked */
  .state-toggle {
    display: flex; gap: 0.375rem; margin-bottom: 0.375rem;
    background: var(--color-bg); border: 1px solid var(--color-border);
    border-radius: 0.875rem; padding: 3px; width: fit-content;
  }
  .state-btn {
    padding: 0.375rem 0.875rem; border-radius: 0.625rem;
    background: none; border: none;
    color: var(--color-muted); font-size: 0.875rem; font-family: inherit;
    cursor: pointer; -webkit-tap-highlight-color: transparent; transition: all 0.15s;
  }
  .state-btn.active { background: var(--color-card); color: var(--color-text); font-weight: 600; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
  .coeff-hint { font-size: 0.75rem; color: var(--color-muted); margin: 0 0 0.875rem; }

  /* Macro grid (2×2) */
  .macro-grid {
    display: grid; grid-template-columns: 1fr 1fr;
    gap: 0.5rem; margin-bottom: 0.875rem;
  }
  .macro-cell {
    background: var(--color-bg); border: 1px solid var(--color-border);
    border-radius: 0.875rem; padding: 0.75rem 0.875rem;
    display: flex; flex-direction: column; gap: 2px;
  }
  .macro-cell.cal { grid-column: 1 / -1; flex-direction: row; align-items: center; gap: 1rem; }
  .macro-cell-val  { font-size: 1.375rem; font-weight: 700; color: var(--color-text); font-family: "JetBrains Mono", monospace; line-height: 1; }
  .macro-cell.cal .macro-cell-val { font-size: 2rem; }
  .macro-cell-lbl  { font-size: 0.72rem; color: var(--color-muted); }
  .macro-cell-pct  { font-size: 0.72rem; color: var(--color-success); margin-left: auto; }

  .per100g { font-size: 0.75rem; color: var(--color-muted); margin: -0.375rem 0 0.875rem; text-align: center; }

  .save-btn {
    width: 100%; padding: 0.9375rem;
    background: var(--color-success); color: white;
    border: none; border-radius: 1rem; font-size: 1.0625rem; font-weight: 600;
    font-family: inherit; cursor: pointer;
    -webkit-tap-highlight-color: transparent; transition: opacity 0.15s;
  }
  .save-btn:disabled { opacity: 0.5; cursor: default; }

  /* ── Misc ── */
  .bottom-spacer { height: calc(5rem + env(safe-area-inset-bottom)); }
</style>
