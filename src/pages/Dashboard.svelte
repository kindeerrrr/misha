<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../lib/supabase'
  import { user } from '../stores/user'
  import { profile, getFirstName } from '../stores/profile'
  import { navigate } from '../stores/nav'
  import { avatar, avatarSrc } from '../stores/avatar'
  import { showToast } from '../stores/toast'
  import { triggerFinanceModal } from '../stores/financeModal'
  import type { Medication, MedicationLog, SleepLog, EmotionEntry, NavTab } from '../lib/types'

  let medications: Medication[] = []
  let pillLogs: MedicationLog[] = []
  let sleepLog: SleepLog | null = null
  let emotions: EmotionEntry[] = []
  let weekExpenses = 0
  let weekWorkouts = 0
  let lastWeight: number | null = null
  let prevWeight: number | null = null
  let upcomingEvents: { icon: string; title: string; date: string; tab: NavTab }[] = []
  let loading = true

  const todayDate = today()
  const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10)
  const in30d = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10)
  const in14d = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10)

  const greeting = (() => {
    const h = new Date().getHours()
    if (h < 6) return 'Доброй ночи'
    if (h < 12) return 'Доброе утро'
    if (h < 17) return 'Добрый день'
    return 'Добрый вечер'
  })()

  const MOOD_EMOJIS = ['😔', '😕', '😐', '🙂', '😄']

  async function logMood(emoji: string) {
    if (!$user) return
    await supabase.from('emotion_entries').insert({
      user_id: $user.id,
      emoji,
      date: todayDate,
      recorded_at: new Date().toISOString(),
    })
    emotions = [...emotions, { id: '', user_id: $user.id, emoji, date: todayDate, recorded_at: new Date().toISOString(), note: null, created_at: new Date().toISOString() }]
  }

  function formatDateRu(iso: string): string {
    const d = new Date(iso + 'T00:00:00')
    return d.toLocaleDateString('ru', { day: 'numeric', month: 'short' })
  }

  async function load() {
    if (!$user) return
    const uid = $user.id

    const [
      medsRes, logsRes, sleepRes, emotRes,
      expRes, workoutsRes,
      weightRes, weightPrevRes,
      checkupsRes, creditsRes, tripsRes
    ] = await Promise.all([
      supabase.from('medications').select('*').eq('user_id', uid).eq('status', 'active'),
      supabase.from('medication_logs').select('*').eq('user_id', uid).eq('date', todayDate),
      supabase.from('sleep_logs').select('*').eq('user_id', uid).eq('date', todayDate).maybeSingle(),
      supabase.from('emotion_entries').select('*').eq('user_id', uid).eq('date', todayDate).order('recorded_at', { ascending: false }),
      supabase.from('expenses').select('amount, tx_type').eq('user_id', uid).gte('date', weekAgo),
      supabase.from('workout_logs').select('id').eq('user_id', uid).gte('date', weekAgo),
      supabase.from('daily_weights').select('weight_kg, date').eq('user_id', uid).order('date', { ascending: false }).limit(1),
      supabase.from('daily_weights').select('weight_kg, date').eq('user_id', uid).lte('date', weekAgo).order('date', { ascending: false }).limit(1),
      supabase.from('annual_checkups').select('name, next_due_at').eq('user_id', uid).lte('next_due_at', in30d).gte('next_due_at', todayDate).order('next_due_at').limit(3),
      supabase.from('credit_payments').select('date, amount, notes').eq('user_id', uid).eq('paid', false).lte('date', in14d).gte('date', todayDate).order('date').limit(3),
      supabase.from('trips').select('title, start_date').eq('user_id', uid).lte('start_date', in30d).gte('start_date', todayDate).order('start_date').limit(3),
    ])

    medications = medsRes.data ?? []
    pillLogs = logsRes.data ?? []
    sleepLog = sleepRes.data
    emotions = emotRes.data ?? []
    weekExpenses = (expRes.data ?? [])
      .filter((r: { tx_type?: string }) => !r.tx_type || r.tx_type === 'expense')
      .reduce((s: number, r: { amount: number }) => s + r.amount, 0)
    weekWorkouts = (workoutsRes.data ?? []).length
    lastWeight = weightRes.data?.[0]?.weight_kg ?? null
    prevWeight = weightPrevRes.data?.[0]?.weight_kg ?? null

    const events: typeof upcomingEvents = []
    for (const c of (checkupsRes.data ?? [])) {
      events.push({ icon: '🩺', title: c.name, date: formatDateRu(c.next_due_at), tab: 'health' })
    }
    for (const p of (creditsRes.data ?? [])) {
      events.push({ icon: '💳', title: p.notes ?? 'Платёж по кредиту', date: formatDateRu(p.date), tab: 'credits' })
    }
    for (const t of (tripsRes.data ?? [])) {
      events.push({ icon: '✈️', title: t.title, date: formatDateRu(t.start_date), tab: 'travel' })
    }
    events.sort((a, b) => a.date.localeCompare(b.date))
    upcomingEvents = events.slice(0, 4)

    loading = false
  }

  $: takenMedIds = new Set(pillLogs.filter(l => !l.skipped).map(l => l.medication_id))
  $: takenCount = takenMedIds.size
  $: nextMed = medications.find(m => !takenMedIds.has(m.id))

  function formatSleep(log: SleepLog | null): string {
    if (!log?.duration_minutes) return '—'
    const h = Math.floor(log.duration_minutes / 60)
    const m = log.duration_minutes % 60
    return m > 0 ? `${h}ч ${m}м` : `${h}ч`
  }

  function sleepStars(log: SleepLog | null): string {
    if (!log?.quality) return ''
    return '★'.repeat(log.quality) + '☆'.repeat(5 - log.quality)
  }

  function weightDelta(last: number | null, prev: number | null): string {
    if (!last) return '—'
    if (!prev) return `${last} кг`
    const d = last - prev
    if (Math.abs(d) < 0.05) return `${last} кг`
    const sign = d > 0 ? '↑' : '↓'
    return `${last} кг ${sign}${Math.abs(d).toFixed(1)}`
  }

  onMount(load)
</script>

<div class="page-shell">
  <!-- Header -->
  <header class="dash-header">
    <div class="header-left">
      <p class="greeting-label">{greeting}{getFirstName($profile) ? `, ${getFirstName($profile)}` : ''}</p>
      <h1 class="dash-title">Как дела?</h1>
    </div>
    <div class="header-right">
      <span class="header-date">
        {new Date().toLocaleDateString('ru', { day: 'numeric', month: 'short' })}
      </span>
      <img src={avatarSrc($avatar)} alt="misha" class="header-avatar" />
    </div>
  </header>

  {#if loading}
    <div class="skeleton-list">
      {#each [1,2,3,4] as _}
        <div class="skeleton-card" />
      {/each}
    </div>
  {:else}
    <!-- Section 1: 2×2 compact grid -->
    <section class="dash-section">
      <div class="compact-grid">

        <!-- Pills card -->
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="compact-card tap-target" on:click={() => navigate('health', 'pills')}>
          <div class="compact-icon">💊</div>
          <div class="compact-body">
            <span class="compact-label">Таблетки</span>
            <span class="compact-value">{takenCount}/{medications.length}</span>
            {#if nextMed}
              <span class="compact-sub">{nextMed.name}</span>
            {:else if medications.length > 0}
              <span class="compact-sub compact-done">Все приняты ✓</span>
            {:else}
              <span class="compact-sub">Нет препаратов</span>
            {/if}
          </div>
        </div>

        <!-- Sleep card -->
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="compact-card tap-target" on:click={() => navigate('health', 'sleep')}>
          <div class="compact-icon">😴</div>
          <div class="compact-body">
            <span class="compact-label">Сон</span>
            <span class="compact-value">{formatSleep(sleepLog)}</span>
            {#if sleepLog?.quality}
              <span class="compact-sub stars">{sleepStars(sleepLog)}</span>
            {:else}
              <span class="compact-sub">Не записан</span>
            {/if}
          </div>
        </div>

        <!-- Weight card -->
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="compact-card tap-target" on:click={() => navigate('health', 'measurements')}>
          <div class="compact-icon">⚖️</div>
          <div class="compact-body">
            <span class="compact-label">Вес</span>
            <span class="compact-value weight-val">{weightDelta(lastWeight, prevWeight)}</span>
            <span class="compact-sub">vs прошлая неделя</span>
          </div>
        </div>

        <!-- Mood card -->
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="compact-card" on:click={() => navigate('emotions')}>
          <div class="compact-icon">💭</div>
          <div class="compact-body">
            <span class="compact-label">Настроение</span>
            <div class="mood-picker">
              {#each MOOD_EMOJIS as emoji}
                <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
                <span
                  class="mood-btn"
                  on:click|stopPropagation={() => logMood(emoji)}
                  title={emoji}
                >{emoji}</span>
              {/each}
            </div>
            {#if emotions.length > 0}
              <span class="compact-sub">сегодня {emotions.length} {emotions.length === 1 ? 'запись' : 'записей'}</span>
            {:else}
              <span class="compact-sub">Отметь как себя</span>
            {/if}
          </div>
        </div>

      </div>
    </section>

    <!-- Section 2: Quick input bar -->
    <section class="dash-section">
      <div class="quick-bar">
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="quick-pill tap-target" on:click={() => navigate('food')}>
          <span class="quick-icon">🍎</span>
          <span>Еда</span>
        </div>
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="quick-pill tap-target" on:click={() => { triggerFinanceModal.set(true); navigate('finances') }}>
          <span class="quick-icon">💰</span>
          <span>Трата</span>
        </div>
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="quick-pill tap-target" on:click={() => navigate('health', 'workouts')}>
          <span class="quick-icon">🏃</span>
          <span>Тренировка</span>
        </div>
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="quick-pill tap-target" on:click={() => showToast('Скоро', 'info')}>
          <span class="quick-icon">🎤</span>
          <span>Голос</span>
        </div>
      </div>
    </section>

    <!-- Section 3: Upcoming events -->
    <section class="dash-section">
      <p class="section-label">Ближайшие события</p>
      <div class="card">
        {#if upcomingEvents.length === 0}
          <p class="empty-hint">Нет ближайших событий</p>
        {:else}
          <div class="events-list">
            {#each upcomingEvents as ev}
              <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
              <div class="event-row tap-target" on:click={() => navigate(ev.tab)}>
                <span class="event-icon">{ev.icon}</span>
                <span class="event-title">{ev.title}</span>
                <span class="event-date">{ev.date}</span>
              </div>
            {/each}
          </div>
        {/if}
      </div>
    </section>

    <!-- Section 4: Weekly trends 2×2 -->
    <section class="dash-section">
      <p class="section-label">За неделю</p>
      <div class="trends-grid">
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="trend-card tap-target" on:click={() => navigate('finances')}>
          <span class="trend-icon">💰</span>
          <span class="trend-label">Траты</span>
          <span class="trend-value number-display">{weekExpenses.toLocaleString('ru')} ₽</span>
        </div>
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="trend-card tap-target" on:click={() => navigate('health', 'workouts')}>
          <span class="trend-icon">🏃</span>
          <span class="trend-label">Активность</span>
          <span class="trend-value number-display">{weekWorkouts} тр.</span>
        </div>
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="trend-card tap-target" on:click={() => navigate('food')}>
          <span class="trend-icon">🍎</span>
          <span class="trend-label">Калории</span>
          <span class="trend-value number-display">—</span>
        </div>
        <a class="trend-card" href="https://notion.so" target="_blank" rel="noopener">
          <span class="trend-icon">📋</span>
          <span class="trend-label">Задачи</span>
          <span class="trend-value notion-link-label">Notion →</span>
        </a>
      </div>
    </section>
  {/if}
</div>

<style>
  .page-shell {
    max-width: 480px;
    margin: 0 auto;
    padding: 0 1.375rem 6rem;
    min-height: 100dvh;
  }

  /* ── Header ── */
  .dash-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    padding: 1.25rem 0 1rem;
  }

  .header-left { flex: 1; }

  .greeting-label {
    font-size: 0.8125rem;
    color: var(--color-muted);
    margin: 0 0 0.2rem;
  }

  .dash-title {
    font-family: "Fraunces", serif;
    font-size: 1.625rem;
    font-weight: 300;
    color: var(--color-text);
    margin: 0;
    letter-spacing: -0.02em;
  }

  .header-right {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 0.375rem;
    padding-top: 0.125rem;
  }

  .header-date {
    font-size: 0.8125rem;
    color: var(--color-muted);
  }

  .header-avatar {
    width: 2.25rem;
    height: 2.25rem;
    border-radius: 0.625rem;
    flex-shrink: 0;
  }

  /* ── Sections ── */
  .dash-section { margin-bottom: 1.375rem; }

  .section-label {
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted);
    margin: 0 0 0.5rem 0.25rem;
  }

  /* ── Compact 2×2 grid ── */
  .compact-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.625rem;
  }

  .compact-card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    padding: 0.875rem 0.875rem 0.75rem;
    min-height: 88px;
    display: flex;
    flex-direction: row;
    align-items: flex-start;
    gap: 0.625rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: opacity 0.15s;
  }

  .compact-icon {
    font-size: 1.25rem;
    flex-shrink: 0;
    margin-top: 0.125rem;
  }

  .compact-body {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 0.125rem;
    min-width: 0;
  }

  .compact-label {
    font-size: 0.6875rem;
    color: var(--color-muted);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .compact-value {
    font-family: "JetBrains Mono", monospace;
    font-size: 1.0625rem;
    color: var(--color-text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .weight-val {
    font-size: 0.9375rem;
  }

  .compact-sub {
    font-size: 0.6875rem;
    color: var(--color-muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .compact-done { color: var(--color-accent); }

  .stars { color: var(--color-accent); letter-spacing: 1px; }

  /* Mood picker inline */
  .mood-picker {
    display: flex;
    gap: 0.1875rem;
    margin: 0.1875rem 0;
  }

  .mood-btn {
    font-size: 1.1rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: transform 0.1s;
    line-height: 1;
  }

  .mood-btn:active { transform: scale(1.3); }

  /* ── Quick bar ── */
  .quick-bar {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 0.5rem;
  }

  .quick-pill {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.25rem;
    padding: 0.75rem 0.25rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1rem;
    cursor: pointer;
    font-size: 0.75rem;
    color: var(--color-text);
    -webkit-tap-highlight-color: transparent;
    transition: opacity 0.15s;
  }

  .quick-icon { font-size: 1.375rem; }

  /* ── Upcoming events ── */
  .card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    padding: 0.875rem 1rem;
  }

  .events-list { display: flex; flex-direction: column; }

  .event-row {
    display: flex;
    align-items: center;
    gap: 0.625rem;
    padding: 0.5625rem 0;
    border-bottom: 1px solid var(--color-border);
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
  }

  .event-row:last-child { border-bottom: none; }

  .event-icon { font-size: 1.125rem; flex-shrink: 0; }

  .event-title {
    flex: 1;
    font-size: 0.9rem;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .event-date {
    font-size: 0.75rem;
    color: var(--color-muted);
    flex-shrink: 0;
  }

  .empty-hint {
    font-size: 0.8125rem;
    color: var(--color-muted);
    margin: 0;
    text-align: center;
    padding: 0.5rem 0;
  }

  /* ── Trends 2×2 ── */
  .trends-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.625rem;
  }

  .trend-card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    padding: 0.875rem;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: opacity 0.15s;
    text-decoration: none;
  }

  .trend-icon { font-size: 1.25rem; }

  .trend-label {
    font-size: 0.6875rem;
    color: var(--color-muted);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .trend-value {
    font-family: "JetBrains Mono", monospace;
    font-size: 1.125rem;
    color: var(--color-text);
  }

  .notion-link-label {
    font-family: inherit;
    font-size: 0.9375rem;
    color: var(--color-accent);
  }

  /* ── Shared ── */
  .tap-target:active { opacity: 0.75; }

  /* ── Skeleton ── */
  .skeleton-list { display: flex; flex-direction: column; gap: 0.75rem; padding-top: 0.5rem; }
  .skeleton-card {
    height: 6rem;
    border-radius: 1.25rem;
    background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover, var(--color-border)) 50%, var(--color-card) 75%);
    background-size: 200% 100%;
    animation: shimmer 1.4s infinite;
  }

  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }
</style>
