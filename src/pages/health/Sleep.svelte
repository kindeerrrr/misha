<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../../lib/supabase'
  import { user } from '../../stores/user'
  import Modal from '../../components/ui/Modal.svelte'
  import StarRating from '../../components/ui/StarRating.svelte'
  import type { SleepLog } from '../../lib/types'

  let logs: SleepLog[] = []
  let todayLog: SleepLog | null = null
  let loading = true
  let showModal = false

  const todayDate = today()

  // Form
  let bedtime = ''
  let wakeTime = ''
  let quality = 0
  let notes = ''
  let saving = false

  async function load() {
    if (!$user) return
    const { data } = await supabase
      .from('sleep_logs').select('*')
      .eq('user_id', $user.id)
      .order('date', { ascending: false })
      .limit(14)
    logs = data ?? []
    todayLog = logs.find(l => l.date === todayDate) ?? null
    if (todayLog) {
      if (todayLog.bedtime) bedtime = new Date(todayLog.bedtime).toTimeString().slice(0,5)
      if (todayLog.wake_time) wakeTime = new Date(todayLog.wake_time).toTimeString().slice(0,5)
      quality = todayLog.quality ?? 0
      notes = todayLog.notes ?? ''
    }
    loading = false
  }

  function calcDuration(bed: string, wake: string): number | null {
    if (!bed || !wake) return null
    const [bh, bm] = bed.split(':').map(Number)
    const [wh, wm] = wake.split(':').map(Number)
    let mins = (wh * 60 + wm) - (bh * 60 + bm)
    if (mins < 0) mins += 24 * 60
    return mins
  }

  async function save() {
    if (!$user) return
    saving = true
    const bedIso = bedtime ? (() => {
      const d = new Date()
      const [h, m] = bedtime.split(':').map(Number)
      // if bedtime is late evening (>= 20), it's yesterday relative to wake
      d.setHours(h, m, 0, 0)
      return d.toISOString()
    })() : null
    const wakeIso = wakeTime ? (() => {
      const d = new Date()
      const [h, m] = wakeTime.split(':').map(Number)
      d.setHours(h, m, 0, 0)
      return d.toISOString()
    })() : null
    const duration = calcDuration(bedtime, wakeTime)

    const payload = {
      user_id: $user.id,
      date: todayDate,
      bedtime: bedIso,
      wake_time: wakeIso,
      duration_minutes: duration,
      quality: quality || null,
      notes: notes || null,
    }

    if (todayLog) {
      const { data } = await supabase.from('sleep_logs').update(payload).eq('id', todayLog.id).select().single()
      if (data) { todayLog = data; logs = logs.map(l => l.id === data.id ? data : l) }
    } else {
      const { data } = await supabase.from('sleep_logs').insert(payload).select().single()
      if (data) { todayLog = data; logs = [data, ...logs] }
    }
    showModal = false
    saving = false
  }

  function formatDuration(mins: number | null): string {
    if (!mins) return '—'
    return `${Math.floor(mins/60)}ч ${mins%60 > 0 ? mins%60+'м' : ''}`
  }

  onMount(load)
</script>

<div>
  <div class="today-section">
    <div class="section-row">
      <h2 class="section-title">Прошлая ночь</h2>
      <button class="edit-btn" on:click={() => showModal = true}>
        {todayLog ? 'Изменить' : '+ Добавить'}
      </button>
    </div>

    {#if loading}
      <div class="skeleton" style="height:6rem" />
    {:else if todayLog}
      <div class="sleep-card">
        <div class="sleep-main">
          <span class="sleep-duration number-display">{formatDuration(todayLog.duration_minutes)}</span>
          {#if todayLog.quality}
            <StarRating value={todayLog.quality} readonly size="sm" />
          {/if}
        </div>
        <div class="sleep-times">
          {#if todayLog.bedtime}
            <span class="time-chip">🌙 {new Date(todayLog.bedtime).toLocaleTimeString('ru', {hour:'2-digit',minute:'2-digit'})}</span>
          {/if}
          {#if todayLog.wake_time}
            <span class="time-chip">☀️ {new Date(todayLog.wake_time).toLocaleTimeString('ru', {hour:'2-digit',minute:'2-digit'})}</span>
          {/if}
        </div>
        {#if todayLog.notes}
          <p class="sleep-notes">{todayLog.notes}</p>
        {/if}
      </div>
    {:else}
      <div class="empty-state" on:click={() => showModal = true} role="button" tabindex="0" on:keypress={() => showModal = true}>
        <p>Запиши сон — тапни чтобы добавить</p>
      </div>
    {/if}
  </div>

  <!-- History -->
  {#if logs.filter(l => l.date !== todayDate).length > 0}
    <div class="history-section">
      <p class="label mb-3 mt-4">История</p>
      <div class="history-list">
        {#each logs.filter(l => l.date !== todayDate).slice(0,10) as log}
          <div class="history-row">
            <span class="history-date">{new Date(log.date).toLocaleDateString('ru', { weekday:'short', day:'numeric', month:'short' })}</span>
            <span class="history-dur number-display">{formatDuration(log.duration_minutes)}</span>
            {#if log.quality}
              <span class="history-stars">{'★'.repeat(log.quality)}</span>
            {/if}
          </div>
        {/each}
      </div>
    </div>
  {/if}
</div>

<Modal title="Сон" open={showModal} on:close={() => showModal = false}>
  <div class="form-stack">
    <div class="time-fields">
      <div class="form-field">
        <label class="label" for="bedtime">🌙 Отбой</label>
        <input id="bedtime" type="time" bind:value={bedtime} />
      </div>
      <div class="form-field">
        <label class="label" for="wake-time">☀️ Подъём</label>
        <input id="wake-time" type="time" bind:value={wakeTime} />
      </div>
    </div>

    {#if bedtime && wakeTime}
      <p class="calc-duration">
        Длительность: <strong>{formatDuration(calcDuration(bedtime, wakeTime))}</strong>
      </p>
    {/if}

    <div class="form-field">
      <label class="label">Качество сна</label>
      <StarRating value={quality} on:change={e => quality = e.detail} />
    </div>

    <div class="form-field">
      <label class="label" for="sleep-notes">Заметка</label>
      <textarea id="sleep-notes" bind:value={notes} rows="2" placeholder="Долго не мог уснуть, часто просыпался..." />
    </div>

    <button class="btn-primary" on:click={save} disabled={saving}>
      {saving ? 'Сохраняю...' : 'Сохранить'}
    </button>
  </div>
</Modal>

<style>
  .today-section { margin-bottom: 0.5rem; }

  .section-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 0.875rem;
  }

  .edit-btn {
    background: none;
    border: 1px solid var(--color-border);
    border-radius: 0.625rem;
    padding: 0.375rem 0.875rem;
    font-size: 0.8125rem;
    color: var(--color-accent);
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
  }

  .sleep-card {
    background-color: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    padding: 1.125rem;
    display: flex;
    flex-direction: column;
    gap: 0.625rem;
  }

  .sleep-main {
    display: flex;
    align-items: center;
    gap: 0.875rem;
  }

  .sleep-duration {
    font-size: 2rem;
    color: var(--color-text);
    line-height: 1;
  }

  .sleep-times { display: flex; gap: 0.625rem; }

  .time-chip {
    font-size: 0.8125rem;
    background-color: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 0.5rem;
    padding: 0.25rem 0.625rem;
  }

  .sleep-notes {
    font-size: 0.8125rem;
    color: var(--color-muted);
    margin: 0;
  }

  .empty-state {
    background-color: var(--color-card);
    border: 1px dashed var(--color-border);
    border-radius: 1.25rem;
    padding: 2rem;
    text-align: center;
    color: var(--color-muted);
    font-size: 0.9375rem;
    cursor: pointer;
  }

  .history-list { display: flex; flex-direction: column; gap: 0; }

  .history-row {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.625rem 0;
    border-bottom: 1px solid var(--color-border);
  }

  .history-date { flex: 1; font-size: 0.875rem; color: var(--color-muted); }
  .history-dur { font-size: 0.9375rem; color: var(--color-text); }
  .history-stars { font-size: 0.8125rem; color: var(--color-accent); letter-spacing: 1px; }

  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; }

  .time-fields { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }

  .calc-duration {
    font-size: 0.875rem;
    color: var(--color-muted);
    margin: -0.5rem 0 0;
    text-align: center;
  }

  .skeleton {
    border-radius: 1.25rem;
    background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%);
    background-size: 200% 100%;
    animation: shimmer 1.4s infinite;
  }

  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .mt-4 { margin-top: 1rem; }
  .mb-3 { margin-bottom: 0.75rem; }
</style>
