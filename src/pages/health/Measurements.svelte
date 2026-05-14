<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../../lib/supabase'
  import { user } from '../../stores/user'
  import Modal from '../../components/ui/Modal.svelte'
  import type { DailyWeight, WeeklyMeasurement } from '../../lib/types'

  let dailyWeights: DailyWeight[] = []
  let weeklyMeasurements: WeeklyMeasurement[] = []
  let loading = true
  let mode: 'daily' | 'weekly' = 'daily'
  let showModal = false

  const todayDate = today()
  const todayWeight = () => dailyWeights.find(w => w.date === todayDate)

  // Forms
  let weightVal = ''
  // Weekly extras
  let waterPct = '', musclePct = '', fatPct = '', bonePct = ''
  let chestCm = '', waistCm = '', hipsCm = ''
  let saving = false

  async function load() {
    if (!$user) return
    const uid = $user.id
    const [wRes, wmRes] = await Promise.all([
      supabase.from('daily_weights').select('*').eq('user_id', uid).order('date', { ascending: false }).limit(30),
      supabase.from('weekly_measurements').select('*').eq('user_id', uid).order('date', { ascending: false }).limit(10),
    ])
    dailyWeights = wRes.data ?? []
    weeklyMeasurements = wmRes.data ?? []
    const existing = dailyWeights.find(w => w.date === todayDate)
    if (existing) weightVal = String(existing.weight_kg)
    loading = false
  }

  async function saveDaily() {
    if (!$user || !weightVal) return
    saving = true
    const kg = parseFloat(weightVal)
    if (isNaN(kg)) { saving = false; return }

    const existing = dailyWeights.find(w => w.date === todayDate)
    if (existing) {
      await supabase.from('daily_weights').update({ weight_kg: kg }).eq('id', existing.id)
      dailyWeights = dailyWeights.map(w => w.date === todayDate ? { ...w, weight_kg: kg } : w)
    } else {
      const { data } = await supabase.from('daily_weights').insert({
        user_id: $user.id, date: todayDate, weight_kg: kg
      }).select().single()
      if (data) dailyWeights = [data, ...dailyWeights]
    }
    showModal = false
    saving = false
  }

  async function saveWeekly() {
    if (!$user) return
    saving = true
    const payload = {
      user_id: $user.id, date: todayDate,
      weight_kg: parseFloat(weightVal) || null,
      water_pct: parseFloat(waterPct) || null,
      muscle_pct: parseFloat(musclePct) || null,
      fat_pct: parseFloat(fatPct) || null,
      bone_kg: parseFloat(bonePct) || null,
      chest_cm: parseFloat(chestCm) || null,
      waist_cm: parseFloat(waistCm) || null,
      hips_cm: parseFloat(hipsCm) || null,
    }
    const existing = weeklyMeasurements.find(w => w.date === todayDate)
    if (existing) {
      await supabase.from('weekly_measurements').update(payload).eq('id', existing.id)
    } else {
      const { data } = await supabase.from('weekly_measurements').insert(payload).select().single()
      if (data) weeklyMeasurements = [data, ...weeklyMeasurements]
    }
    showModal = false
    saving = false
  }

  function lastWeight(): string {
    const w = dailyWeights[0]
    return w ? `${w.weight_kg} кг` : '—'
  }

  onMount(load)
</script>

<div>
  <!-- Mode toggle -->
  <div class="mode-toggle">
    <button class="mode-btn" class:active={mode === 'daily'} on:click={() => mode = 'daily'}>Ежедневно</button>
    <button class="mode-btn" class:active={mode === 'weekly'} on:click={() => mode = 'weekly'}>Еженедельно</button>
  </div>

  {#if mode === 'daily'}
    <div class="section-row mt-3">
      <div>
        <h2 class="section-title">Вес</h2>
        <p class="label">{lastWeight()}</p>
      </div>
      <button class="edit-btn" on:click={() => { mode='daily'; showModal = true }}>
        {todayWeight() ? 'Изменить' : '+ Сегодня'}
      </button>
    </div>

    {#if loading}
      <div class="skeleton" style="height:5rem" />
    {:else}
      <div class="weight-list mt-3">
        {#each dailyWeights.slice(0, 14) as w}
          <div class="weight-row">
            <span class="weight-date">{new Date(w.date).toLocaleDateString('ru', {day:'numeric', month:'short', weekday:'short'})}</span>
            <span class="weight-val number-display">{w.weight_kg} кг</span>
          </div>
        {/each}
      </div>
    {/if}

  {:else}
    <!-- Weekly -->
    <div class="section-row mt-3">
      <h2 class="section-title">Замеры с весов</h2>
      <button class="edit-btn" on:click={() => { mode='weekly'; showModal = true }}>+ Сегодня</button>
    </div>

    {#if weeklyMeasurements.length === 0}
      <div class="empty-state">Заполни расширенные данные с весов раз в неделю</div>
    {:else}
      {#each weeklyMeasurements.slice(0,5) as m}
        <div class="weekly-card">
          <div class="weekly-date label">{new Date(m.date).toLocaleDateString('ru', {day:'numeric', month:'long'})}</div>
          <div class="weekly-grid">
            {#if m.weight_kg}<div class="metric"><span class="metric-val number-display">{m.weight_kg}</span><span class="metric-label">кг</span></div>{/if}
            {#if m.fat_pct}<div class="metric"><span class="metric-val number-display">{m.fat_pct}</span><span class="metric-label">% жир</span></div>{/if}
            {#if m.muscle_pct}<div class="metric"><span class="metric-val number-display">{m.muscle_pct}</span><span class="metric-label">% мышцы</span></div>{/if}
            {#if m.water_pct}<div class="metric"><span class="metric-val number-display">{m.water_pct}</span><span class="metric-label">% вода</span></div>{/if}
            {#if m.waist_cm}<div class="metric"><span class="metric-val number-display">{m.waist_cm}</span><span class="metric-label">талия см</span></div>{/if}
            {#if m.hips_cm}<div class="metric"><span class="metric-val number-display">{m.hips_cm}</span><span class="metric-label">бёдра см</span></div>{/if}
            {#if m.chest_cm}<div class="metric"><span class="metric-val number-display">{m.chest_cm}</span><span class="metric-label">грудь см</span></div>{/if}
          </div>
        </div>
      {/each}
    {/if}
  {/if}
</div>

<Modal title={mode === 'daily' ? 'Вес сегодня' : 'Замеры с весов'} open={showModal} on:close={() => showModal = false}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="weight-input">Вес (кг)</label>
      <input id="weight-input" type="number" step="0.1" bind:value={weightVal} placeholder="68.5" inputmode="decimal" />
    </div>

    {#if mode === 'weekly'}
      <div class="grid2">
        <div class="form-field">
          <label class="label" for="water">Вода %</label>
          <input id="water" type="number" step="0.1" bind:value={waterPct} placeholder="50.0" inputmode="decimal" />
        </div>
        <div class="form-field">
          <label class="label" for="muscle">Мышцы %</label>
          <input id="muscle" type="number" step="0.1" bind:value={musclePct} placeholder="32.0" inputmode="decimal" />
        </div>
        <div class="form-field">
          <label class="label" for="fat">Жир %</label>
          <input id="fat" type="number" step="0.1" bind:value={fatPct} placeholder="35.0" inputmode="decimal" />
        </div>
        <div class="form-field">
          <label class="label" for="bone">Костная масса кг</label>
          <input id="bone" type="number" step="0.1" bind:value={bonePct} placeholder="2.8" inputmode="decimal" />
        </div>
        <div class="form-field">
          <label class="label" for="chest">Грудь см</label>
          <input id="chest" type="number" step="0.5" bind:value={chestCm} placeholder="96" inputmode="decimal" />
        </div>
        <div class="form-field">
          <label class="label" for="waist">Талия см</label>
          <input id="waist" type="number" step="0.5" bind:value={waistCm} placeholder="82" inputmode="decimal" />
        </div>
        <div class="form-field">
          <label class="label" for="hips">Бёдра см</label>
          <input id="hips" type="number" step="0.5" bind:value={hipsCm} placeholder="105" inputmode="decimal" />
        </div>
      </div>
    {/if}

    <button class="btn-primary" on:click={mode === 'daily' ? saveDaily : saveWeekly} disabled={saving}>
      {saving ? 'Сохраняю...' : 'Сохранить'}
    </button>
  </div>
</Modal>

<style>
  .mode-toggle {
    display: flex;
    background-color: var(--color-card);
    border-radius: 0.875rem;
    padding: 0.25rem;
    gap: 0.25rem;
    border: 1px solid var(--color-border);
  }

  .mode-btn {
    flex: 1;
    padding: 0.5rem;
    border: none;
    border-radius: 0.625rem;
    font-size: 0.875rem;
    background: none;
    color: var(--color-muted);
    cursor: pointer;
    transition: background-color 0.15s, color 0.15s;
    -webkit-tap-highlight-color: transparent;
  }

  .mode-btn.active {
    background-color: var(--color-accent);
    color: white;
  }

  .section-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .edit-btn {
    background: none;
    border: 1px solid var(--color-border);
    border-radius: 0.625rem;
    padding: 0.375rem 0.875rem;
    font-size: 0.8125rem;
    color: var(--color-accent);
    cursor: pointer;
  }

  .weight-list { display: flex; flex-direction: column; }

  .weight-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.625rem 0;
    border-bottom: 1px solid var(--color-border);
  }

  .weight-date { font-size: 0.875rem; color: var(--color-muted); }
  .weight-val { font-size: 1rem; }

  .weekly-card {
    background-color: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    padding: 1rem;
    margin-bottom: 0.75rem;
  }

  .weekly-date { margin-bottom: 0.75rem; }

  .weekly-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 0.5rem;
  }

  .metric {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    background-color: var(--color-bg);
    border-radius: 0.625rem;
    padding: 0.5rem 0.25rem;
  }

  .metric-val { font-size: 1rem; color: var(--color-text); }
  .metric-label { font-size: 0.625rem; color: var(--color-muted); text-align: center; }

  .empty-state {
    padding: 2rem;
    text-align: center;
    color: var(--color-muted);
    font-size: 0.9375rem;
    background: var(--color-card);
    border-radius: 1.25rem;
    border: 1px dashed var(--color-border);
  }

  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; }
  .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }

  .skeleton {
    border-radius: 1.25rem;
    background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%);
    background-size: 200% 100%;
    animation: shimmer 1.4s infinite;
  }

  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .mt-3 { margin-top: 0.75rem; }
</style>
