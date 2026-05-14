<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../lib/supabase'
  import { user } from '../stores/user'
  import Modal from '../components/ui/Modal.svelte'
  import StarRating from '../components/ui/StarRating.svelte'
  import type { EmotionEntry, DayReport } from '../lib/types'

  let emotions: EmotionEntry[] = []
  let dayReport: DayReport | null = null
  let loading = true
  let showEmoModal = false
  let showDayModal = false

  const todayDate = today()

  // Emoji modal
  let selEmoji = ''
  let emoNote = ''
  let emoDate = todayDate
  let savingEmo = false

  // Day report
  let drOverall = 0
  let drEnergy = 0
  let drAnxiety = 0
  let drProductivity = 0
  let drWarmth = 0
  let drHighlight = ''
  let drLow = ''
  let drGratitude = ''
  let drDate = todayDate
  let savingDr = false

  const EMOJIS = [
    '😊','😄','🥰','😌','😎','🤩',
    '😐','🤔','😴','😤','😢','😰',
    '😔','😩','🥺','😭','😡','🤯',
    '🌟','✨','💪','🌱','🍀','❤️',
  ]

  async function load() {
    if (!$user) return
    const uid = $user.id
    const [emoRes, drRes] = await Promise.all([
      supabase.from('emotion_entries').select('*').eq('user_id', uid).order('recorded_at', { ascending: false }).limit(50),
      supabase.from('day_reports').select('*').eq('user_id', uid).eq('date', todayDate).maybeSingle(),
    ])
    emotions = emoRes.data ?? []
    dayReport = drRes.data
    if (dayReport) {
      drOverall = dayReport.overall ?? 0
      drEnergy = dayReport.energy ?? 0
      drAnxiety = dayReport.anxiety ?? 0
      drProductivity = dayReport.productivity ?? 0
      drWarmth = dayReport.warmth ?? 0
      drHighlight = dayReport.highlight ?? ''
      drLow = dayReport.low_point ?? ''
      drGratitude = dayReport.gratitude ?? ''
    }
    loading = false
  }

  async function saveEmotion() {
    if (!$user || !selEmoji) return
    savingEmo = true
    const { data } = await supabase.from('emotion_entries').insert({
      user_id: $user.id,
      emoji: selEmoji,
      note: emoNote || null,
      date: emoDate,
      recorded_at: emoDate === todayDate ? new Date().toISOString() : `${emoDate}T12:00:00Z`,
    }).select().single()
    if (data) emotions = [data, ...emotions]
    showEmoModal = false
    selEmoji = ''; emoNote = ''; emoDate = todayDate
    savingEmo = false
  }

  async function saveDayReport() {
    if (!$user) return
    savingDr = true
    const payload = {
      user_id: $user.id,
      date: drDate,
      overall: drOverall || null,
      energy: drEnergy || null,
      anxiety: drAnxiety || null,
      productivity: drProductivity || null,
      warmth: drWarmth || null,
      highlight: drHighlight || null,
      low_point: drLow || null,
      gratitude: drGratitude || null,
    }
    if (dayReport && drDate === todayDate) {
      const { data } = await supabase.from('day_reports').update(payload).eq('id', dayReport.id).select().single()
      if (data) dayReport = data
    } else {
      const { data } = await supabase.from('day_reports').insert(payload).select().single()
      if (data) dayReport = data
    }
    showDayModal = false
    savingDr = false
  }

  function todayEmotions(): EmotionEntry[] {
    return emotions.filter(e => e.date === todayDate)
  }

  function pastEmotions(): EmotionEntry[] {
    return emotions.filter(e => e.date !== todayDate)
  }

  function groupByDate(entries: EmotionEntry[]): [string, EmotionEntry[]][] {
    const groups: Record<string, EmotionEntry[]> = {}
    for (const e of entries) {
      if (!groups[e.date]) groups[e.date] = []
      groups[e.date].push(e)
    }
    return Object.entries(groups).slice(0, 7)
  }

  function formatDate(d: string): string {
    const yesterday = new Date()
    yesterday.setDate(yesterday.getDate() - 1)
    const ds = yesterday.toISOString().slice(0, 10)
    if (d === ds) return 'Вчера'
    return new Date(d).toLocaleDateString('ru', { weekday: 'long', day: 'numeric', month: 'short' })
  }

  onMount(load)
</script>

<div class="page-shell">
  <header class="page-header">
    <h1 class="section-title">Эмоции и день</h1>
    <div class="header-actions">
      <button class="header-btn" on:click={() => showEmoModal = true}>+✦</button>
      <button class="header-btn" on:click={() => showDayModal = true}>📝</button>
    </div>
  </header>

  {#if loading}
    <div class="skeleton" style="height:5rem" />
  {:else}
    <!-- Today -->
    <section class="today-emotions">
      <p class="label mb-2">Сегодня</p>
      <div class="emo-quick-row">
        {#each todayEmotions() as e}
          <div class="emo-chip">
            <span class="emo-emoji">{e.emoji}</span>
            {#if e.note}<span class="emo-note">{e.note}</span>{/if}
          </div>
        {/each}
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="add-emo-btn" on:click={() => showEmoModal = true}>+ как ты?</div>
      </div>
    </section>

    <!-- Day report today -->
    <section class="day-report-card mt-3">
      <div class="dr-header">
        <p class="label">Как прошёл день</p>
        <button class="edit-btn" on:click={() => showDayModal = true}>
          {dayReport ? 'Изменить' : '+ Заполнить'}
        </button>
      </div>
      {#if dayReport}
        <div class="dr-metrics">
          {#each [
            ['Общее', dayReport.overall],
            ['Энергия', dayReport.energy],
            ['Тревога', dayReport.anxiety],
            ['Продукт.', dayReport.productivity],
            ['Тепло', dayReport.warmth],
          ] as [label, val]}
            {#if val}
              <div class="dr-metric">
                <span class="dr-label">{label}</span>
                <span class="dr-val number-display">{val}/5</span>
              </div>
            {/if}
          {/each}
        </div>
        {#if dayReport.highlight}
          <p class="dr-text">✦ {dayReport.highlight}</p>
        {/if}
        {#if dayReport.gratitude}
          <p class="dr-text">🙏 {dayReport.gratitude}</p>
        {/if}
      {:else}
        <p class="empty-hint">Вечером или утром следующего дня — за 3 минуты</p>
      {/if}
    </section>

    <!-- Past emotions grouped by date -->
    {#if pastEmotions().length > 0}
      <section class="history mt-4">
        <p class="label mb-2">История</p>
        {#each groupByDate(pastEmotions()) as [date, entries]}
          <div class="history-day">
            <span class="history-date">{formatDate(date)}</span>
            <div class="emo-strip">
              {#each entries as e}
                <span class="emo-emoji" title={e.note ?? ''}>{e.emoji}</span>
              {/each}
            </div>
          </div>
        {/each}
      </section>
    {/if}
  {/if}
</div>

<!-- Emotion modal -->
<Modal title="Как ты сейчас?" open={showEmoModal} on:close={() => { showEmoModal = false; selEmoji = '' }}>
  <div class="form-stack">
    <div class="emoji-grid">
      {#each EMOJIS as e}
        <button
          class="emoji-btn"
          class:selected={selEmoji === e}
          on:click={() => selEmoji = e}
        >{e}</button>
      {/each}
    </div>

    <div class="form-field">
      <label class="label" for="emo-note">Заметка (необязательно)</label>
      <textarea id="emo-note" bind:value={emoNote} rows="2" placeholder="Пара слов о настроении..." />
    </div>

    <div class="form-field">
      <label class="label" for="emo-date">Дата</label>
      <input id="emo-date" type="date" bind:value={emoDate} />
    </div>

    <button class="btn-primary" on:click={saveEmotion} disabled={savingEmo || !selEmoji}>
      {savingEmo ? 'Сохраняю...' : 'Сохранить'}
    </button>
  </div>
</Modal>

<!-- Day report modal -->
<Modal title="Как прошёл день?" open={showDayModal} on:close={() => showDayModal = false}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="dr-date">Дата</label>
      <input id="dr-date" type="date" bind:value={drDate} />
    </div>

    <div class="form-field">
      <label class="label">Общее самочувствие</label>
      <StarRating value={drOverall} on:change={e => drOverall = e.detail} />
    </div>
    <div class="form-field">
      <label class="label">Энергия</label>
      <StarRating value={drEnergy} on:change={e => drEnergy = e.detail} />
    </div>
    <div class="form-field">
      <label class="label">Тревожность (1=низкая)</label>
      <StarRating value={drAnxiety} on:change={e => drAnxiety = e.detail} />
    </div>
    <div class="form-field">
      <label class="label">Продуктивность</label>
      <StarRating value={drProductivity} on:change={e => drProductivity = e.detail} />
    </div>
    <div class="form-field">
      <label class="label">Тепло в отношениях</label>
      <StarRating value={drWarmth} on:change={e => drWarmth = e.detail} />
    </div>

    <div class="form-field">
      <label class="label" for="dr-highlight">Главное за день ✦</label>
      <textarea id="dr-highlight" bind:value={drHighlight} rows="2" placeholder="Что хорошего произошло?" />
    </div>

    <div class="form-field">
      <label class="label" for="dr-low">Сложный момент</label>
      <textarea id="dr-low" bind:value={drLow} rows="2" placeholder="Что было непросто?" />
    </div>

    <div class="form-field">
      <label class="label" for="dr-gratitude">Благодарность</label>
      <textarea id="dr-gratitude" bind:value={drGratitude} rows="2" placeholder="За что благодарна сегодня?" />
    </div>

    <button class="btn-primary" on:click={saveDayReport} disabled={savingDr}>
      {savingDr ? 'Сохраняю...' : 'Сохранить'}
    </button>
  </div>
</Modal>

<style>
  .page-shell {
    max-width: 480px;
    margin: 0 auto;
    padding: 0 1.375rem 6rem;
  }

  .page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 0 0.75rem;
  }

  .header-actions { display: flex; gap: 0.5rem; }

  .header-btn {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    padding: 0.5rem 0.75rem;
    font-size: 0.9375rem;
    cursor: pointer;
    color: var(--color-accent);
    -webkit-tap-highlight-color: transparent;
  }

  .today-emotions { margin-bottom: 0.5rem; }

  .emo-quick-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: flex-start;
  }

  .emo-chip {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 2rem;
    padding: 0.375rem 0.75rem;
  }

  .emo-emoji { font-size: 1.375rem; line-height: 1; }
  .emo-note { font-size: 0.8125rem; color: var(--color-muted); max-width: 8rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  .add-emo-btn {
    padding: 0.375rem 0.875rem;
    border: 1px dashed var(--color-border);
    border-radius: 2rem;
    font-size: 0.875rem;
    color: var(--color-accent);
    cursor: pointer;
    background: none;
    -webkit-tap-highlight-color: transparent;
  }

  .day-report-card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    padding: 1rem;
  }

  .dr-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 0.75rem;
  }

  .edit-btn { background: none; border: 1px solid var(--color-border); border-radius: 0.625rem; padding: 0.25rem 0.625rem; font-size: 0.8125rem; color: var(--color-accent); cursor: pointer; }

  .dr-metrics { display: flex; gap: 0.5rem; flex-wrap: wrap; margin-bottom: 0.5rem; }
  .dr-metric { display: flex; flex-direction: column; align-items: center; background: var(--color-bg); border-radius: 0.625rem; padding: 0.375rem 0.625rem; gap: 2px; }
  .dr-label { font-size: 0.625rem; color: var(--color-muted); text-transform: uppercase; letter-spacing: 0.04em; }
  .dr-val { font-size: 0.875rem; color: var(--color-text); }
  .dr-text { font-size: 0.875rem; color: var(--color-muted); margin: 0.25rem 0 0; }

  .empty-hint { font-size: 0.8125rem; color: var(--color-muted); margin: 0; }

  .history-day {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.625rem 0;
    border-bottom: 1px solid var(--color-border);
  }

  .history-date { font-size: 0.8125rem; color: var(--color-muted); min-width: 6rem; }
  .emo-strip { display: flex; gap: 0.25rem; flex-wrap: wrap; }

  .emoji-grid { display: grid; grid-template-columns: repeat(6, 1fr); gap: 0.375rem; }
  .emoji-btn { font-size: 1.5rem; background: var(--color-card); border: 1.5px solid var(--color-border); border-radius: 0.75rem; aspect-ratio: 1; display: flex; align-items: center; justify-content: center; cursor: pointer; -webkit-tap-highlight-color: transparent; transition: all 0.1s; }
  .emoji-btn.selected { border-color: var(--color-accent); background: var(--color-accent); }
  .emoji-btn:active { transform: scale(0.92); }

  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; }

  .skeleton { border-radius: 1.25rem; background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .mt-3 { margin-top: 0.75rem; }
  .mt-4 { margin-top: 1rem; }
  .mb-2 { margin-bottom: 0.5rem; }
</style>
