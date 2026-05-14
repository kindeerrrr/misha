<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../../lib/supabase'
  import { user } from '../../stores/user'
  import Modal from '../../components/ui/Modal.svelte'
  import type { Medication, MedicationLog, MedicationCriticality, MedicationFrequency, MedicationStatus } from '../../lib/types'

  let medications: Medication[] = []
  let todayLogs: MedicationLog[] = []
  let loading = true
  let showAddModal = false
  let showHistoryId = ''

  const todayDate = today()

  // Form state
  let newName = ''
  let newFrequency: MedicationFrequency = 'daily'
  let newTime = 'evening'
  let newCriticality: MedicationCriticality = 'medium'
  let newStatus: MedicationStatus = 'active'
  let newNotes = ''
  let saving = false

  async function load() {
    if (!$user) return
    const [medsRes, logsRes] = await Promise.all([
      supabase.from('medications').select('*').eq('user_id', $user.id).order('criticality'),
      supabase.from('medication_logs').select('*').eq('user_id', $user.id).eq('date', todayDate),
    ])
    medications = medsRes.data ?? []
    todayLogs = logsRes.data ?? []
    loading = false
  }

  function isTaken(med: Medication) {
    return todayLogs.some(l => l.medication_id === med.id && !l.skipped)
  }

  async function toggleMed(med: Medication) {
    if (!$user) return
    const existing = todayLogs.find(l => l.medication_id === med.id && !l.skipped)
    if (existing) {
      await supabase.from('medication_logs').delete().eq('id', existing.id)
      todayLogs = todayLogs.filter(l => l.id !== existing.id)
    } else {
      const { data } = await supabase.from('medication_logs').insert({
        user_id: $user.id,
        medication_id: med.id,
        taken_at: new Date().toISOString(),
        skipped: false,
        date: todayDate,
      }).select().single()
      if (data) todayLogs = [...todayLogs, data]
    }
  }

  async function addMedication() {
    if (!$user || !newName.trim()) return
    saving = true
    const { data } = await supabase.from('medications').insert({
      user_id: $user.id,
      name: newName.trim(),
      frequency: newFrequency,
      time_of_day: newTime,
      criticality: newCriticality,
      status: newStatus,
      notes: newNotes || null,
    }).select().single()
    if (data) medications = [...medications, data]
    showAddModal = false
    resetForm()
    saving = false
  }

  async function toggleStatus(med: Medication) {
    if (!$user) return
    const newSt: MedicationStatus = med.status === 'active' ? 'paused' : 'active'
    await supabase.from('medications').update({ status: newSt }).eq('id', med.id)
    medications = medications.map(m => m.id === med.id ? { ...m, status: newSt } : m)
  }

  async function deleteMed(id: string) {
    if (!$user) return
    await supabase.from('medications').delete().eq('id', id)
    medications = medications.filter(m => m.id !== id)
  }

  function resetForm() {
    newName = ''; newFrequency = 'daily'; newTime = 'evening'
    newCriticality = 'medium'; newStatus = 'active'; newNotes = ''
  }

  const critColors: Record<MedicationCriticality, string> = {
    high: 'var(--color-danger)',
    medium: 'var(--color-accent2)',
    low: 'var(--color-muted)',
  }

  const critLabel: Record<MedicationCriticality, string> = {
    high: '! Высокая', medium: 'Средняя', low: 'Низкая'
  }

  const freqLabel: Record<MedicationFrequency, string> = {
    daily: 'Ежедневно', twice_daily: '2 раза в день',
    weekdays: 'По будням', weekly: 'Раз в неделю', custom: 'По расписанию'
  }

  onMount(load)
</script>

<div>
  <!-- Today header -->
  <div class="today-header">
    <h2 class="section-title">Сегодня</h2>
    <span class="progress-badge">
      {todayLogs.filter(l => !l.skipped).length} / {medications.filter(m => m.status === 'active').length}
    </span>
  </div>

  {#if loading}
    <div class="skeleton" style="height:8rem" />
  {:else if medications.filter(m => m.status === 'active').length === 0}
    <div class="empty-state">
      <p>Добавь первый препарат</p>
    </div>
  {:else}
    <div class="med-list">
      {#each medications.filter(m => m.status === 'active') as med}
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div
          class="med-card"
          class:taken={isTaken(med)}
          on:click={() => toggleMed(med)}
        >
          <div class="med-check">{isTaken(med) ? '✓' : ''}</div>
          <div class="med-info">
            <span class="med-name">{med.name}</span>
            <span class="med-freq">{freqLabel[med.frequency]} · {med.time_of_day ?? ''}</span>
          </div>
          <div class="med-crit" style="color: {critColors[med.criticality]}">
            {med.criticality === 'high' ? '!' : ''}
          </div>
        </div>
      {/each}
    </div>
  {/if}

  <!-- Planned / Paused -->
  {#if medications.filter(m => m.status !== 'active').length > 0}
    <div class="planned-section">
      <p class="label mb-2 mt-4">Неактивные</p>
      {#each medications.filter(m => m.status !== 'active') as med}
        <div class="med-card-inactive">
          <div class="med-info">
            <span class="med-name muted">{med.name}</span>
            <span class="med-freq">{med.status === 'planned' ? 'Планируется' : 'Пауза'} · {freqLabel[med.frequency]}</span>
          </div>
          <button class="activate-btn" on:click={() => toggleStatus(med)}>
            {med.status === 'planned' ? 'Начать' : 'Возобновить'}
          </button>
        </div>
      {/each}
    </div>
  {/if}

  <!-- Add button -->
  <button class="btn-primary mt-4" on:click={() => showAddModal = true}>
    + Добавить препарат
  </button>
</div>

<!-- Add modal -->
<Modal title="Новый препарат" open={showAddModal} on:close={() => { showAddModal = false; resetForm() }}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="med-name">Название</label>
      <input id="med-name" type="text" bind:value={newName} placeholder="Например, Железо" />
    </div>

    <div class="form-field">
      <label class="label">Частота</label>
      <div class="radio-group">
        {#each [['daily','Ежедневно'],['twice_daily','2×/день'],['weekdays','По будням'],['weekly','Раз в неделю']] as [val, lbl]}
          <label class="radio-pill" class:selected={newFrequency === val}>
            <input type="radio" bind:group={newFrequency} value={val} />
            {lbl}
          </label>
        {/each}
      </div>
    </div>

    <div class="form-field">
      <label class="label" for="med-time">Время приёма</label>
      <select id="med-time" bind:value={newTime}>
        <option value="morning">Утром</option>
        <option value="afternoon">Днём</option>
        <option value="evening">Вечером</option>
        <option value="with_food">С едой</option>
      </select>
    </div>

    <div class="form-field">
      <label class="label">Критичность</label>
      <div class="radio-group">
        {#each [['high','! Высокая'],['medium','Средняя'],['low','Низкая']] as [val, lbl]}
          <label class="radio-pill" class:selected={newCriticality === val}>
            <input type="radio" bind:group={newCriticality} value={val} />
            {lbl}
          </label>
        {/each}
      </div>
    </div>

    <div class="form-field">
      <label class="label">Статус</label>
      <div class="radio-group">
        <label class="radio-pill" class:selected={newStatus === 'active'}>
          <input type="radio" bind:group={newStatus} value="active" /> Активен
        </label>
        <label class="radio-pill" class:selected={newStatus === 'planned'}>
          <input type="radio" bind:group={newStatus} value="planned" /> Планируется
        </label>
      </div>
    </div>

    <div class="form-field">
      <label class="label" for="med-notes">Заметка (опционально)</label>
      <textarea id="med-notes" bind:value={newNotes} rows="2" placeholder="Например, принимать за 30 мин до еды" />
    </div>

    <button class="btn-primary mt-2" on:click={addMedication} disabled={saving || !newName.trim()}>
      {saving ? 'Сохраняю...' : 'Добавить'}
    </button>
  </div>
</Modal>

<style>
  .today-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 0.875rem;
  }

  .progress-badge {
    font-family: "JetBrains Mono", monospace;
    font-size: 0.875rem;
    background-color: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.625rem;
    padding: 0.25rem 0.625rem;
    color: var(--color-accent);
  }

  .med-list { display: flex; flex-direction: column; gap: 0.5rem; }

  .med-card {
    display: flex;
    align-items: center;
    gap: 0.875rem;
    padding: 0.875rem 1rem;
    background-color: var(--color-card);
    border: 1.5px solid var(--color-border);
    border-radius: 1rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
  }

  .med-card:active { transform: scale(0.98); }

  .med-card.taken {
    background-color: var(--color-accent);
    border-color: var(--color-accent);
    color: white;
  }

  .med-check {
    width: 1.5rem;
    height: 1.5rem;
    border-radius: 50%;
    border: 1.5px solid var(--color-border);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.875rem;
    flex-shrink: 0;
    transition: border-color 0.15s;
  }

  .med-card.taken .med-check { border-color: rgba(255,255,255,0.5); }

  .med-info { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .med-name { font-size: 0.9375rem; }
  .med-freq { font-size: 0.75rem; opacity: 0.7; }
  .med-crit { font-size: 1rem; font-weight: 700; width: 1rem; text-align: center; }

  .med-card-inactive {
    display: flex;
    align-items: center;
    gap: 0.875rem;
    padding: 0.75rem 1rem;
    background-color: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1rem;
    margin-bottom: 0.5rem;
  }

  .med-name.muted { color: var(--color-muted); }

  .activate-btn {
    padding: 0.375rem 0.875rem;
    border: 1px solid var(--color-accent);
    background: none;
    color: var(--color-accent);
    border-radius: 0.625rem;
    font-size: 0.8125rem;
    cursor: pointer;
    white-space: nowrap;
    -webkit-tap-highlight-color: transparent;
  }

  .empty-state {
    text-align: center;
    padding: 2rem 0;
    color: var(--color-muted);
    font-size: 0.9375rem;
  }

  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; }

  .radio-group { display: flex; flex-wrap: wrap; gap: 0.375rem; }

  .radio-pill {
    padding: 0.375rem 0.875rem;
    border: 1px solid var(--color-border);
    border-radius: 2rem;
    font-size: 0.8125rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: background-color 0.15s, border-color 0.15s, color 0.15s;
  }

  .radio-pill.selected {
    background-color: var(--color-accent);
    border-color: var(--color-accent);
    color: white;
  }

  .radio-pill input { display: none; }

  .skeleton {
    border-radius: 1.25rem;
    background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%);
    background-size: 200% 100%;
    animation: shimmer 1.4s infinite;
  }

  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .muted { color: var(--color-muted); }
  .mt-4 { margin-top: 1rem; }
  .mt-2 { margin-top: 0.5rem; }
  .mb-2 { margin-bottom: 0.5rem; }
</style>
