<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../../lib/supabase'
  import { user } from '../../stores/user'
  import Modal from '../../components/ui/Modal.svelte'
  import StarRating from '../../components/ui/StarRating.svelte'
  import type { WorkoutType, WorkoutLog } from '../../lib/types'

  let workoutTypes: WorkoutType[] = []
  let logs: WorkoutLog[] = []
  let loading = true
  let showLogModal = false
  let showTypeModal = false

  const todayDate = today()

  // Log form
  let selTypeId = ''
  let duration = ''
  let intensity = 0
  let wNotes = ''
  let wDate = todayDate
  let saving = false

  // Type form
  let newTypeName = ''

  async function load() {
    if (!$user) return
    const uid = $user.id
    const [typesRes, logsRes] = await Promise.all([
      supabase.from('workout_types').select('*').eq('user_id', uid).order('name'),
      supabase.from('workout_logs').select('*, workout_types(name, icon)').eq('user_id', uid).order('date', { ascending: false }).limit(30),
    ])
    workoutTypes = typesRes.data ?? []
    logs = (logsRes.data ?? []).map((l: WorkoutLog & { workout_types?: WorkoutType }) => ({
      ...l, workout_type: l.workout_types
    }))
    loading = false
  }

  async function logWorkout() {
    if (!$user || !selTypeId || !duration) return
    saving = true
    const { data } = await supabase.from('workout_logs').insert({
      user_id: $user.id,
      workout_type_id: selTypeId,
      date: wDate,
      duration_minutes: parseInt(duration),
      intensity: intensity || null,
      notes: wNotes || null,
    }).select('*, workout_types(name, icon)').single()
    if (data) {
      const log: WorkoutLog = { ...data, workout_type: data.workout_types }
      logs = [log, ...logs]
    }
    showLogModal = false
    selTypeId = ''; duration = ''; intensity = 0; wNotes = ''; wDate = todayDate
    saving = false
  }

  async function addType() {
    if (!$user || !newTypeName.trim()) return
    const { data } = await supabase.from('workout_types').insert({
      user_id: $user.id,
      name: newTypeName.trim(),
      icon: '',
      is_default: false,
    }).select().single()
    if (data) workoutTypes = [...workoutTypes, data]
    showTypeModal = false
    newTypeName = ''
  }

  async function deleteLog(id: string) {
    if (!$user) return
    await supabase.from('workout_logs').delete().eq('id', id)
    logs = logs.filter(l => l.id !== id)
  }

  function groupByDate() {
    const groups: Record<string, WorkoutLog[]> = {}
    for (const log of logs) {
      if (!groups[log.date]) groups[log.date] = []
      groups[log.date].push(log)
    }
    return Object.entries(groups).slice(0, 10)
  }

  function formatDate(d: string): string {
    return new Date(d).toLocaleDateString('ru', { weekday: 'short', day: 'numeric', month: 'short' })
  }

  onMount(load)
</script>

<div>
  <div class="section-row">
    <h2 class="section-title">Тренировки</h2>
    <button class="edit-btn" on:click={() => showLogModal = true}>+ Добавить</button>
  </div>

  <!-- Type chips -->
  {#if workoutTypes.length > 0}
    <div class="type-chips">
      {#each workoutTypes as t}
        <button
          class="type-chip"
          class:selected={selTypeId === t.id}
          on:click={() => { selTypeId = t.id; showLogModal = true }}
        >
          {t.name}
        </button>
      {/each}
      <button class="type-chip add-type" on:click={() => showTypeModal = true}>+ свой тип</button>
    </div>
  {:else}
    <button class="btn-ghost mt-3" on:click={() => showTypeModal = true}>+ Добавить тип тренировки</button>
  {/if}

  <!-- Log -->
  {#if loading}
    <div class="skeleton mt-4" style="height:8rem" />
  {:else if logs.length === 0}
    <div class="empty-state mt-4">Выбери тип выше и залогируй первую тренировку</div>
  {:else}
    <div class="log-list mt-4">
      {#each groupByDate() as [date, dayLogs]}
        <div class="day-group">
          <p class="label mb-1">{formatDate(date)}</p>
          {#each dayLogs as log}
            <div class="log-row">
              <span class="log-name">{log.workout_type?.name ?? '—'}</span>
              <span class="log-dur number-display">{log.duration_minutes}м</span>
              {#if log.intensity}
                <span class="log-int">{'●'.repeat(log.intensity)}{'○'.repeat(5-log.intensity)}</span>
              {/if}
              <button class="del-btn" on:click={() => deleteLog(log.id)}>×</button>
            </div>
          {/each}
        </div>
      {/each}
    </div>
  {/if}
</div>

<!-- Log modal -->
<Modal title="Тренировка" open={showLogModal} on:close={() => { showLogModal = false; selTypeId = '' }}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label">Тип</label>
      <div class="type-grid">
        {#each workoutTypes as t}
          <button class="type-btn" class:selected={selTypeId === t.id} on:click={() => selTypeId = t.id}>
            <span>{t.name}</span>
          </button>
        {/each}
      </div>
    </div>

    <div class="form-field">
      <label class="label" for="w-date">Дата</label>
      <input id="w-date" type="date" bind:value={wDate} />
    </div>

    <div class="form-field">
      <label class="label" for="w-dur">Длительность (мин)</label>
      <input id="w-dur" type="number" bind:value={duration} placeholder="60" inputmode="numeric" />
    </div>

    <div class="form-field">
      <label class="label">Интенсивность</label>
      <StarRating value={intensity} on:change={e => intensity = e.detail} />
    </div>

    <div class="form-field">
      <label class="label" for="w-notes">Заметка</label>
      <textarea id="w-notes" bind:value={wNotes} rows="2" placeholder="Кардио 20 мин, жим 3×10..." />
    </div>

    <button class="btn-primary" on:click={logWorkout} disabled={saving || !selTypeId || !duration}>
      {saving ? 'Сохраняю...' : 'Сохранить'}
    </button>
  </div>
</Modal>

<!-- Add type modal -->
<Modal title="Новый тип тренировки" open={showTypeModal} on:close={() => showTypeModal = false}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="type-name">Название</label>
      <input id="type-name" type="text" bind:value={newTypeName} placeholder="Например, Скандинавская ходьба" />
    </div>
    <button class="btn-primary" on:click={addType} disabled={!newTypeName.trim()}>Добавить</button>
  </div>
</Modal>

<style>
  .section-row { display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.875rem; }
  .edit-btn { background: none; border: 1px solid var(--color-border); border-radius: 0.625rem; padding: 0.375rem 0.875rem; font-size: 0.8125rem; color: var(--color-accent); cursor: pointer; }

  .type-chips { display: flex; flex-wrap: wrap; gap: 0.375rem; margin-top: 0.5rem; }

  .type-chip {
    padding: 0.375rem 0.875rem;
    border: 1px solid var(--color-border);
    border-radius: 2rem;
    background: var(--color-card);
    font-size: 0.875rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
  }

  .type-chip.selected { background-color: var(--color-accent); border-color: var(--color-accent); color: white; }
  .add-type { color: var(--color-accent); }

  .log-list { display: flex; flex-direction: column; gap: 1rem; }
  .day-group { display: flex; flex-direction: column; gap: 0.375rem; }

  .log-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.625rem 0.875rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
  }

  .log-icon { font-size: 1rem; }
  .log-name { flex: 1; font-size: 0.9375rem; }
  .log-dur { font-size: 0.875rem; }
  .log-int { font-size: 0.75rem; color: var(--color-accent); letter-spacing: 1px; }
  .del-btn { background: none; border: none; color: var(--color-muted); font-size: 1.25rem; cursor: pointer; padding: 0 0.25rem; line-height: 1; }

  .empty-state { padding: 2rem; text-align: center; color: var(--color-muted); background: var(--color-card); border-radius: 1.25rem; border: 1px dashed var(--color-border); }

  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; }

  .type-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 0.5rem; }
  .type-btn { display: flex; flex-direction: column; align-items: center; gap: 4px; padding: 0.625rem; border: 1px solid var(--color-border); border-radius: 0.875rem; background: var(--color-card); cursor: pointer; font-size: 0.8125rem; -webkit-tap-highlight-color: transparent; transition: all 0.15s; }
  .type-btn.selected { background: var(--color-accent); border-color: var(--color-accent); color: white; }

  .icon-picker { display: flex; flex-wrap: wrap; gap: 0.5rem; }
  .icon-btn { width: 2.75rem; height: 2.75rem; border: 1px solid var(--color-border); border-radius: 0.75rem; background: var(--color-card); font-size: 1.25rem; cursor: pointer; display: flex; align-items: center; justify-content: center; -webkit-tap-highlight-color: transparent; }
  .icon-btn.selected { border-color: var(--color-accent); background: var(--color-accent); }

  .skeleton { border-radius: 1.25rem; background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .mt-3 { margin-top: 0.75rem; }
  .mt-4 { margin-top: 1rem; }
  .mb-1 { margin-bottom: 0.25rem; }
</style>
