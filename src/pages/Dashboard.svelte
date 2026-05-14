<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../lib/supabase'
  import { user } from '../stores/user'
  import { navigate } from '../stores/nav'
  import Card from '../components/ui/Card.svelte'
  import type { Medication, MedicationLog, SleepLog, EmotionEntry, Expense } from '../lib/types'

  let medications: Medication[] = []
  let todayLogs: MedicationLog[] = []
  let sleepLog: SleepLog | null = null
  let emotions: EmotionEntry[] = []
  let weekExpenses = 0
  let loading = true

  const todayDate = today()
  const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10)

  const greeting = (() => {
    const h = new Date().getHours()
    if (h < 6) return 'Доброй ночи'
    if (h < 12) return 'Доброе утро'
    if (h < 17) return 'Добрый день'
    return 'Добрый вечер'
  })()

  async function load() {
    if (!$user) return
    const uid = $user.id

    const [medsRes, logsRes, sleepRes, emotRes, expRes] = await Promise.all([
      supabase.from('medications').select('*').eq('user_id', uid).eq('status', 'active'),
      supabase.from('medication_logs').select('*').eq('user_id', uid).eq('date', todayDate),
      supabase.from('sleep_logs').select('*').eq('user_id', uid).eq('date', todayDate).maybeSingle(),
      supabase.from('emotion_entries').select('*').eq('user_id', uid).eq('date', todayDate).order('recorded_at', { ascending: false }),
      supabase.from('expenses').select('amount').eq('user_id', uid).gte('date', weekAgo),
    ])

    medications = medsRes.data ?? []
    todayLogs = logsRes.data ?? []
    sleepLog = sleepRes.data
    emotions = emotRes.data ?? []
    weekExpenses = (expRes.data ?? []).reduce((sum: number, r: {amount: number}) => sum + r.amount, 0)
    loading = false
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

  function isTaken(med: Medication) {
    return todayLogs.some(l => l.medication_id === med.id && !l.skipped)
  }

  function formatSleep(log: SleepLog | null): string {
    if (!log || !log.duration_minutes) return '—'
    const h = Math.floor(log.duration_minutes / 60)
    const m = log.duration_minutes % 60
    return m > 0 ? `${h}ч ${m}м` : `${h}ч`
  }

  function lastEmoji(): string {
    return emotions[0]?.emoji ?? ''
  }

  onMount(load)
</script>

<div class="page-shell">
  <!-- Header -->
  <header class="dash-header">
    <div>
      <p class="greeting-label">{greeting}</p>
      <h1 class="section-title">Как дела?</h1>
    </div>
    <div class="header-date">
      <span class="number-display">{new Date().toLocaleDateString('ru', { day: 'numeric', month: 'short' })}</span>
    </div>
  </header>

  {#if loading}
    <div class="skeleton-list">
      {#each [1,2,3] as _}
        <div class="skeleton-card" />
      {/each}
    </div>
  {:else}
    <!-- Block 1: Today -->
    <section class="dash-section">
      <p class="label mb-2">Сегодня</p>

      <!-- Pills -->
      <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
      <div class="card mb-3 tap-target" on:click={() => navigate('health', 'pills')}>
        <div class="card-header">
          <span class="card-icon">💊</span>
          <span class="card-title">Таблетки</span>
          <span class="card-badge">{todayLogs.filter(l => !l.skipped).length}/{medications.length}</span>
        </div>
        {#if medications.length === 0}
          <p class="empty-hint">Добавь препараты в разделе Здоровье</p>
        {:else}
          <div class="pill-list">
            {#each medications as med}
              <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
              <div
                class="check-pill"
                class:checked={isTaken(med)}
                on:click|stopPropagation={() => toggleMed(med)}
              >
                <span class="check-box">{isTaken(med) ? '✓' : ''}</span>
                <span class="pill-name">{med.name}</span>
              </div>
            {/each}
          </div>
        {/if}
      </div>

      <!-- Sleep -->
      <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
      <div class="card mb-3 tap-target" on:click={() => navigate('health', 'sleep')}>
        <div class="card-header">
          <span class="card-icon">😴</span>
          <span class="card-title">Сон прошлой ночью</span>
        </div>
        {#if sleepLog}
          <div class="sleep-display">
            <span class="sleep-hours number-display">{formatSleep(sleepLog)}</span>
            {#if sleepLog.quality}
              <span class="sleep-quality">{'★'.repeat(sleepLog.quality)}{'☆'.repeat(5 - sleepLog.quality)}</span>
            {/if}
          </div>
        {:else}
          <p class="empty-hint">Не записан — тапни чтобы добавить</p>
        {/if}
      </div>

      <!-- Emotions quick -->
      <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
      <div class="card tap-target" on:click={() => navigate('emotions')}>
        <div class="card-header">
          <span class="card-icon">✦</span>
          <span class="card-title">Как ты сейчас?</span>
        </div>
        {#if emotions.length > 0}
          <div class="emotion-strip">
            {#each emotions.slice(0, 5) as e}
              <span class="emotion-chip">{e.emoji}</span>
            {/each}
          </div>
        {:else}
          <p class="empty-hint">Отметь настроение →</p>
        {/if}
      </div>
    </section>

    <!-- Block 2: Week dynamics -->
    <section class="dash-section">
      <p class="label mb-2">За неделю</p>

      <!-- Finances quick -->
      <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
      <div class="card tap-target" on:click={() => navigate('finances')}>
        <div class="card-header">
          <span class="card-icon">◎</span>
          <span class="card-title">Траты</span>
        </div>
        <div class="finance-row">
          <span class="finance-amount number-display">{weekExpenses.toLocaleString('ru')} ₽</span>
          <span class="finance-label">за 7 дней</span>
        </div>
      </div>
    </section>

    <!-- Block 3: Open links -->
    <section class="dash-section">
      <p class="label mb-2">Ссылки</p>
      <div class="card">
        <a
          href="https://notion.so"
          target="_blank"
          rel="noopener"
          class="notion-link"
        >
          <span>🗂</span>
          <span>Задачи в Notion</span>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M18 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2h6M15 3h6v6M10 14L21 3"/></svg>
        </a>
      </div>
    </section>
  {/if}
</div>

<style>
  .dash-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    padding: 1rem 0 0.75rem;
  }

  .greeting-label {
    font-size: 0.8125rem;
    color: var(--color-muted);
    margin: 0 0 0.125rem;
  }

  .header-date {
    font-size: 0.875rem;
    color: var(--color-muted);
    padding-top: 0.25rem;
  }

  .dash-section {
    margin-bottom: 1.5rem;
  }

  .card {
    background-color: var(--color-card);
    border-radius: 1.25rem;
    padding: 1rem;
    border: 1px solid var(--color-border);
  }

  .card-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 0.75rem;
  }

  .card-icon { font-size: 1rem; }

  .card-title {
    font-size: 0.9375rem;
    color: var(--color-text);
    flex: 1;
  }

  .card-badge {
    font-family: "JetBrains Mono", monospace;
    font-size: 0.8125rem;
    color: var(--color-accent);
    background-color: var(--color-bg);
    border-radius: 0.5rem;
    padding: 0.125rem 0.5rem;
  }

  .pill-list {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .check-pill {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.625rem 0.875rem;
    background-color: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    cursor: pointer;
    transition: background-color 0.15s, border-color 0.15s;
    -webkit-tap-highlight-color: transparent;
  }

  .check-pill:active { transform: scale(0.98); }

  .check-pill.checked {
    background-color: var(--color-accent);
    border-color: var(--color-accent);
    color: white;
  }

  .check-box {
    width: 1.25rem;
    height: 1.25rem;
    border-radius: 50%;
    border: 1.5px solid var(--color-border);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.75rem;
    flex-shrink: 0;
    transition: background-color 0.15s;
  }

  .check-pill.checked .check-box {
    border-color: white;
    color: white;
  }

  .pill-name { font-size: 0.9375rem; }

  .empty-hint {
    font-size: 0.8125rem;
    color: var(--color-muted);
    margin: 0;
  }

  .sleep-display {
    display: flex;
    align-items: baseline;
    gap: 0.75rem;
  }

  .sleep-hours {
    font-size: 1.75rem;
    color: var(--color-text);
  }

  .sleep-quality {
    color: var(--color-accent);
    font-size: 0.875rem;
    letter-spacing: 1px;
  }

  .emotion-strip {
    display: flex;
    gap: 0.375rem;
    flex-wrap: wrap;
  }

  .emotion-chip {
    font-size: 1.375rem;
    line-height: 1;
  }

  .finance-row {
    display: flex;
    align-items: baseline;
    gap: 0.625rem;
  }

  .finance-amount {
    font-size: 1.5rem;
    color: var(--color-text);
  }

  .finance-label {
    font-size: 0.8125rem;
    color: var(--color-muted);
  }

  .notion-link {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    color: var(--color-text);
    text-decoration: none;
    font-size: 0.9375rem;
  }

  .notion-link span:nth-child(2) { flex: 1; }

  .skeleton-list {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    padding-top: 1rem;
  }

  .skeleton-card {
    height: 6rem;
    border-radius: 1.25rem;
    background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%);
    background-size: 200% 100%;
    animation: shimmer 1.4s infinite;
  }

  @keyframes shimmer {
    from { background-position: 200% 0; }
    to { background-position: -200% 0; }
  }

  .mb-3 { margin-bottom: 0.75rem; }
</style>
