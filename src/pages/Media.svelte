<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import { supabase } from '../lib/supabase'
  import { user } from '../stores/user'
  import Modal from '../components/ui/Modal.svelte'
  import StarRating from '../components/ui/StarRating.svelte'
  import type { MediaItem, MediaType, MediaStatus } from '../lib/types'

  let items: MediaItem[] = []
  let loading = true
  let showModal = false
  let editItem: MediaItem | null = null

  let activeStatus: MediaStatus = 'in_progress'
  let activeType: MediaType | null = null

  // Inline page editing
  let editingPageId: string | null = null
  let editingPageValue = ''

  // Series episode expansion
  let expandedSeriesId: string | null = null
  let selectedSeason: Record<string, number> = {}
  let epsInputValues: Record<string, string> = {}

  // Status move animation
  let movingItemId: string | null = null

  // Reading timer
  let timerItemId: string | null = null
  let timerStart = 0
  let timerInterval: ReturnType<typeof setInterval> | null = null
  let timerDisplay = '0:00'

  // Form state
  let fTitle = ''
  let fType: MediaType = 'book'
  let fGenre = ''
  let fStatus: MediaStatus = 'want'
  let fRating = 0
  let fNotes = ''
  let fTotalPages = ''
  let fCurrentPage = ''
  let fSeasonsTotal = ''
  let fEpisodesPerSeason: number[] = []
  let fFormSeason = 0
  let fSeasonRatings: number[] = []
  let fSeriesFinished = false
  let saving = false

  const typeLabel: Record<MediaType, string> = { book: 'Книга', film: 'Фильм', series: 'Сериал' }
  const typeFilterLabel: Record<MediaType, string> = { book: 'Книги', film: 'Фильмы', series: 'Сериалы' }
  const statusLabel: Record<MediaStatus, string> = { want: 'Хочу', in_progress: 'Читаю / Смотрю', done: 'Готово' }
  const ALL_STATUSES: MediaStatus[] = ['in_progress', 'want', 'done']
  const ALL_TYPES: MediaType[] = ['book', 'film', 'series']
  const FORM_STATUSES: MediaStatus[] = ['want', 'in_progress', 'done']

  async function load() {
    if (!$user) return
    const res = await supabase.from('media_items').select('*').eq('user_id', $user.id).order('created_at', { ascending: false })
    items = res.data ?? []
    loading = false
  }

  $: countByStatus = {
    in_progress: items.filter(i => i.status === 'in_progress').length,
    want: items.filter(i => i.status === 'want').length,
    done: items.filter(i => i.status === 'done').length,
  }

  $: displayItems = (() => {
    const base = items.filter(i => i.status === activeStatus)
    return activeType ? base.filter(i => i.type === activeType) : base
  })()

  $: availableTypes = ALL_TYPES.filter(t => items.some(i => i.type === t))

  function openAdd(status: MediaStatus = activeStatus === 'in_progress' ? 'want' : activeStatus) {
    editItem = null
    fTitle = ''; fType = 'book'; fGenre = ''; fStatus = status
    fRating = 0; fNotes = ''
    fTotalPages = ''; fCurrentPage = ''
    fSeasonsTotal = ''; fEpisodesPerSeason = []; fFormSeason = 0
    fSeasonRatings = []; fSeriesFinished = false
    showModal = true
  }

  function openEdit(item: MediaItem) {
    editItem = item
    fTitle = item.title; fType = item.type; fGenre = item.genre ?? ''
    fStatus = item.status; fRating = item.rating ?? 0; fNotes = item.notes ?? ''
    fTotalPages = item.total_pages?.toString() ?? ''
    fCurrentPage = item.current_page?.toString() ?? ''
    fSeasonsTotal = item.seasons_total?.toString() ?? ''
    fEpisodesPerSeason = [...(item.episodes_per_season ?? [])]
    fFormSeason = Math.max(0, (item.current_season ?? 1) - 1)
    fSeasonRatings = item.season_ratings ?? []
    fSeriesFinished = !!(item.is_finished && item.status !== 'done')
    showModal = true
  }

  async function save() {
    if (!$user || !fTitle.trim()) return
    saving = true
    const n = parseInt(fSeasonsTotal)
    const epsArr = fEpisodesPerSeason.slice(0, isNaN(n) ? 0 : n)
    const payload: Record<string, unknown> = {
      user_id: $user.id,
      title: fTitle.trim(),
      type: fType,
      genre: fGenre || null,
      status: fStatus,
      rating: fRating || null,
      notes: fNotes || null,
      total_pages: fTotalPages ? parseInt(fTotalPages) : null,
      current_page: fCurrentPage ? parseInt(fCurrentPage) : null,
      seasons_total: !isNaN(n) && n > 0 ? n : null,
      is_finished: fStatus === 'done' || fSeriesFinished,
      episodes_per_season: epsArr.some(e => e > 0) ? epsArr : null,
      started_at: fStatus !== 'want' && !editItem?.started_at ? new Date().toISOString() : editItem?.started_at ?? null,
      finished_at: fStatus === 'done' && !editItem?.finished_at ? new Date().toISOString() : editItem?.finished_at ?? null,
    }
    if (editItem) {
      const { data } = await supabase.from('media_items').update(payload).eq('id', editItem.id).select().single()
      if (data) items = items.map(i => i.id === editItem!.id ? data : i)
    } else {
      const { data } = await supabase.from('media_items').insert(payload).select().single()
      if (data) {
        items = [data, ...items]
        activeStatus = fStatus  // switch to the tab showing the new item
        activeType = null
      }
    }
    showModal = false
    saving = false
  }

  async function deleteItem(id: string) {
    await supabase.from('media_items').delete().eq('id', id)
    items = items.filter(i => i.id !== id)
  }

  async function moveStatus(item: MediaItem, status: MediaStatus) {
    movingItemId = item.id
    const updates: Partial<MediaItem> = { status, is_finished: status === 'done' }
    if (status !== 'want' && !item.started_at) updates.started_at = new Date().toISOString()
    if (status === 'done' && !item.finished_at) updates.finished_at = new Date().toISOString()
    await supabase.from('media_items').update(updates).eq('id', item.id)
    await new Promise(r => setTimeout(r, 320))
    items = items.map(i => i.id === item.id ? { ...i, ...updates } : i)
    movingItemId = null
  }

  // Book helpers
  function bookProgress(item: MediaItem): number {
    if (!item.current_page || !item.total_pages) return 0
    return Math.round((item.current_page / item.total_pages) * 100)
  }

  function totalReadingMinutes(item: MediaItem): number {
    return (item.reading_log ?? []).reduce((s, l) => s + l.minutes, 0)
  }

  function formatReadingTime(minutes: number): string {
    if (minutes < 60) return `${minutes} мин`
    const h = Math.floor(minutes / 60)
    const m = minutes % 60
    return m > 0 ? `${h}ч ${m}м` : `${h}ч`
  }

  function startEditPage(item: MediaItem, e: Event) {
    e.stopPropagation()
    editingPageId = item.id
    editingPageValue = item.current_page?.toString() ?? ''
  }

  function commitPage(item: MediaItem) {
    const page = parseInt(editingPageValue)
    if (!isNaN(page) && page >= 0) updateCurrentPage(item, page)
    editingPageId = null; editingPageValue = ''
  }

  async function updateCurrentPage(item: MediaItem, page: number) {
    const updates = { current_page: page }
    items = items.map(i => i.id === item.id ? { ...i, ...updates } : i)
    await supabase.from('media_items').update(updates).eq('id', item.id)
  }

  // Series episode tracking — position-based (current_season + current_episode)
  function getEpsInSeason(item: MediaItem, seasonIdx: number): number {
    return (item.episodes_per_season ?? [])[seasonIdx] ?? 0
  }

  // 'watched' = before current, 'current' = at current, 'remaining' = after
  function getEpisodeState(item: MediaItem, seasonIdx: number, ep: number): 'watched' | 'current' | 'remaining' {
    const curS = item.current_season ?? 0
    const curE = item.current_episode ?? 0
    const s = seasonIdx + 1
    if (curS === 0) return 'remaining'
    if (s < curS) return 'watched'
    if (s === curS && ep < curE) return 'watched'
    if (s === curS && ep === curE) return 'current'
    return 'remaining'
  }

  // How many episodes are "watched" in a given season (episodes before current position)
  function watchedCountInSeason(item: MediaItem, seasonIdx: number): number {
    const s = seasonIdx + 1
    const curS = item.current_season ?? 0
    const curE = item.current_episode ?? 0
    const total = getEpsInSeason(item, seasonIdx)
    if (curS === 0) return 0
    if (s < curS) return total
    if (s === curS) return Math.max(0, curE - 1)
    return 0
  }

  async function setCurrentEpisode(item: MediaItem, seasonIdx: number, ep: number) {
    const s = seasonIdx + 1
    const isCurrent = item.current_season === s && item.current_episode === ep
    let newSeason = s
    let newEp = ep

    if (isCurrent) {
      // Tapping current ep → advance to next
      const epsInSeason = getEpsInSeason(item, seasonIdx)
      if (ep < epsInSeason) {
        newEp = ep + 1
      } else if (s < (item.seasons_total ?? 1)) {
        newSeason = s + 1
        newEp = 1
        selectedSeason = { ...selectedSeason, [item.id]: seasonIdx + 1 }
      }
    }

    const updates = { current_season: newSeason, current_episode: newEp }
    items = items.map(i => i.id === item.id ? { ...i, ...updates } : i)
    await supabase.from('media_items').update(updates).eq('id', item.id)
  }

  async function setEpsInSeason(item: MediaItem, seasonIdx: number, count: number) {
    if (isNaN(count) || count < 1) return
    const arr = [...(item.episodes_per_season ?? [])]
    while (arr.length <= seasonIdx) arr.push(0)
    arr[seasonIdx] = count
    const updates = { episodes_per_season: arr }
    items = items.map(i => i.id === item.id ? { ...i, ...updates } : i)
    await supabase.from('media_items').update(updates).eq('id', item.id)
  }

  function toggleSeriesExpand(item: MediaItem) {
    if (expandedSeriesId === item.id) {
      expandedSeriesId = null
    } else {
      expandedSeriesId = item.id
      if (selectedSeason[item.id] === undefined) {
        selectedSeason = { ...selectedSeason, [item.id]: Math.max(0, (item.current_season ?? 1) - 1) }
      }
    }
  }

  // Reading timer
  function toggleTimer(item: MediaItem) {
    if (timerItemId === item.id) {
      stopAndSaveTimer(item)
    } else {
      if (timerItemId) {
        const running = items.find(i => i.id === timerItemId)
        if (running) stopAndSaveTimer(running)
      }
      timerItemId = item.id
      timerStart = Date.now()
      timerDisplay = '0:00'
      timerInterval = setInterval(() => {
        const elapsed = Math.floor((Date.now() - timerStart) / 1000)
        const m = Math.floor(elapsed / 60)
        const s = elapsed % 60
        timerDisplay = `${m}:${s.toString().padStart(2, '0')}`
      }, 1000)
    }
  }

  async function stopAndSaveTimer(item: MediaItem) {
    if (timerInterval) { clearInterval(timerInterval); timerInterval = null }
    const minutes = Math.round((Date.now() - timerStart) / 60000)
    timerItemId = null; timerDisplay = '0:00'
    if (minutes < 1) return
    const today = new Date().toISOString().slice(0, 10)
    const log = [...(item.reading_log ?? []), { date: today, minutes }]
    const updates = { reading_log: log }
    items = items.map(i => i.id === item.id ? { ...i, ...updates } : i)
    await supabase.from('media_items').update(updates).eq('id', item.id)
  }

  // Season ratings (display only)
  function seasonRatingStars(rating: number): string {
    return '★'.repeat(rating) + '☆'.repeat(5 - rating)
  }

  function setSeasonRating(idx: number, val: number) {
    fSeasonRatings = fSeasonRatings.map((r, i) => i === idx ? val : r)
  }

  // Sync fEpisodesPerSeason & fSeasonRatings length with fSeasonsTotal
  $: {
    const n = parseInt(fSeasonsTotal)
    if (fType === 'series' && !isNaN(n) && n > 0) {
      while (fEpisodesPerSeason.length < n) fEpisodesPerSeason.push(0)
      fEpisodesPerSeason = fEpisodesPerSeason.slice(0, n)
      while (fSeasonRatings.length < n) fSeasonRatings.push(0)
      fSeasonRatings = fSeasonRatings.slice(0, n)
      if (fFormSeason >= n) fFormSeason = 0
    }
  }

  onMount(load)
  onDestroy(() => { if (timerInterval) clearInterval(timerInterval) })
</script>

<div class="page-shell">
  <header class="page-header">
    <h1 class="section-title">Медиа</h1>
    <button class="add-btn" on:click={() => openAdd('want')}>+ Добавить</button>
  </header>

  <div class="status-tabs">
    {#each ALL_STATUSES as s}
      <button class="status-tab" class:active={activeStatus === s} on:click={() => { activeStatus = s }}>
        {statusLabel[s]}
        {#if countByStatus[s] > 0}<span class="count">{countByStatus[s]}</span>{/if}
      </button>
    {/each}
  </div>

  {#if !loading && availableTypes.length > 0}
    <div class="type-filter-row">
      <button class="filter-chip" class:active={activeType === null} on:click={() => activeType = null}>Все</button>
      {#each availableTypes as t}
        <button class="filter-chip" class:active={activeType === t} on:click={() => activeType = t}>{typeFilterLabel[t]}</button>
      {/each}
    </div>
  {/if}

  {#if loading}
    <div class="skeleton mt-4" style="height:10rem" />
  {:else if displayItems.length === 0}
    <div class="empty-state mt-4">
      {activeStatus === 'want' ? 'Ничего не запланировано' : activeStatus === 'in_progress' ? 'Ничего в процессе' : 'Ещё ничего не закончено'}
    </div>
  {:else}
    <div class="item-list mt-3">
      {#each displayItems as item (item.id)}
        <div class="item-card" class:moving={movingItemId === item.id}>
          <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
          <div class="item-top" on:click={() => openEdit(item)}>
            <div class="item-info">
              <div class="item-badges">
                <span class="item-type-badge">{typeLabel[item.type]}</span>
                {#if item.is_finished && item.status !== 'done'}<span class="finished-badge">завершён</span>{/if}
              </div>
              <span class="item-title">{item.title}</span>
              {#if item.genre}<span class="item-genre">{item.genre}</span>{/if}
            </div>
            <button class="del-btn" on:click|stopPropagation={() => deleteItem(item.id)}>×</button>
          </div>

          <!-- Book: progress + timer -->
          {#if item.type === 'book' && item.status === 'in_progress'}
            <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
            <div class="progress-row" on:click|stopPropagation>
              {#if item.current_page && item.total_pages}
                <div class="progress-bar"><div class="progress-fill" style="width:{bookProgress(item)}%" /></div>
              {/if}
              <span class="progress-label">
                {#if editingPageId === item.id}
                  <!-- svelte-ignore a11y-autofocus -->
                  <input class="page-inline-input" type="number" autofocus bind:value={editingPageValue}
                    on:blur={() => commitPage(item)}
                    on:keydown={e => { if (e.key === 'Enter') commitPage(item); if (e.key === 'Escape') editingPageId = null }}
                    on:click|stopPropagation />
                {:else}
                  <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
                  <span class="page-tappable" on:click={e => startEditPage(item, e)}>{item.current_page ?? '—'}</span>
                {/if}
                {#if item.total_pages} / {item.total_pages} стр.{:else} стр.{/if}
                {#if item.current_page && item.total_pages} · {bookProgress(item)}%{/if}
              </span>
            </div>
            <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
            <div class="timer-row" on:click|stopPropagation>
              <button class="timer-btn" class:active={timerItemId === item.id} on:click={() => toggleTimer(item)}>
                {timerItemId === item.id ? '■' : '▶'}
              </button>
              {#if timerItemId === item.id}
                <span class="timer-display">{timerDisplay}</span>
              {:else if totalReadingMinutes(item) > 0}
                <span class="reading-total">{formatReadingTime(totalReadingMinutes(item))} прочитано</span>
              {:else}
                <span class="reading-total">Таймер чтения</span>
              {/if}
            </div>
          {/if}

          <!-- Series: expandable episode tracker -->
          {#if item.type === 'series' && item.status === 'in_progress'}
            <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
            <div class="series-header" on:click|stopPropagation={() => toggleSeriesExpand(item)}>
              <span class="series-progress-text">
                {#if item.current_season || item.current_episode}
                  {#if item.current_season}С{item.current_season}{item.seasons_total ? '/' + item.seasons_total : ''}{/if}
                  {#if item.current_episode} · Серия {item.current_episode}{/if}
                {:else}
                  <span class="series-not-started">Ещё не начато</span>
                {/if}
              </span>
              <span class="expand-chevron" class:open={expandedSeriesId === item.id}>▾</span>
            </div>

            {#if expandedSeriesId === item.id}
              {@const seasonIdx = selectedSeason[item.id] ?? 0}
              {@const totalSeasons = item.seasons_total ?? 1}
              {@const epsInSeason = getEpsInSeason(item, seasonIdx)}

              <!-- Season tabs -->
              <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
              <div class="season-tabs" on:click|stopPropagation>
                {#each { length: totalSeasons } as _, si}
                  {@const watched = watchedCountInSeason(item, si)}
                  {@const total = getEpsInSeason(item, si)}
                  <button class="season-tab-btn" class:active={seasonIdx === si}
                    on:click={() => selectedSeason = { ...selectedSeason, [item.id]: si }}>
                    Сезон {si + 1}
                    {#if total > 0}<span class="season-tab-count">{watched}/{total}</span>{/if}
                  </button>
                {/each}
              </div>

              <!-- Episode rows OR setup prompt -->
              <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
              <div on:click|stopPropagation>
                {#if epsInSeason > 0}
                  <div class="eps-list">
                    {#each { length: epsInSeason } as _, ei}
                      {@const epNum = ei + 1}
                      {@const st = getEpisodeState(item, seasonIdx, epNum)}
                      <button
                        class="ep-row"
                        class:ep-watched={st === 'watched'}
                        class:ep-current={st === 'current'}
                        class:ep-remaining={st === 'remaining'}
                        on:click={() => setCurrentEpisode(item, seasonIdx, epNum)}
                      >
                        <span class="ep-label">Серия {epNum}</span>
                        <span
                          class="ep-toggle"
                          class:ep-toggle-watched={st === 'watched'}
                          class:ep-toggle-current={st === 'current'}
                          class:ep-toggle-remaining={st === 'remaining'}
                        ></span>
                      </button>
                    {/each}
                  </div>
                {:else}
                  <div class="eps-setup">
                    <span class="eps-setup-label">Серий в сезоне {seasonIdx + 1}:</span>
                    <input class="eps-count-input" type="number" inputmode="numeric" placeholder="10"
                      bind:value={epsInputValues[`${item.id}-${seasonIdx}`]}
                      on:blur={() => { const v = parseInt(epsInputValues[`${item.id}-${seasonIdx}`]); if (!isNaN(v) && v > 0) setEpsInSeason(item, seasonIdx, v) }}
                      on:keydown={e => { if (e.key === 'Enter') { const v = parseInt(epsInputValues[`${item.id}-${seasonIdx}`]); if (!isNaN(v) && v > 0) setEpsInSeason(item, seasonIdx, v); e.currentTarget.blur() } }}
                    />
                  </div>
                {/if}
              </div>
            {/if}
          {/if}

          <!-- Season ratings on done cards -->
          {#if item.type === 'series' && item.status === 'done' && item.season_ratings?.length}
            <div class="season-ratings-row">
              {#each item.season_ratings as sr, idx}
                <span class="season-rating-chip">С{idx + 1} {seasonRatingStars(sr)}</span>
              {/each}
            </div>
          {/if}

          {#if item.rating}
            <div class="item-rating">{'★'.repeat(item.rating)}{'☆'.repeat(5 - item.rating)}</div>
          {/if}
          {#if item.notes}<p class="item-notes">{item.notes}</p>{/if}

          <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
          <div class="item-actions" on:click|stopPropagation>
            {#if activeStatus === 'want'}
              <button class="action-btn" on:click={() => moveStatus(item, 'in_progress')}>Начать →</button>
            {:else if activeStatus === 'in_progress'}
              <button class="action-btn" on:click={() => moveStatus(item, 'done')}>Завершить ✓</button>
            {/if}
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<Modal title={editItem ? 'Редактировать' : 'Новое'} open={showModal} on:close={() => showModal = false}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="m-title">Название</label>
      <input id="m-title" type="text" bind:value={fTitle} placeholder="Название книги, фильма..." />
    </div>

    <div class="form-field">
      <label class="label">Тип</label>
      <div class="type-tabs">
        {#each ALL_TYPES as t}
          <button class="type-tab" class:active={fType === t} on:click={() => fType = t}>{typeLabel[t]}</button>
        {/each}
      </div>
    </div>

    <div class="form-field">
      <label class="label">Статус</label>
      <div class="type-tabs">
        {#each FORM_STATUSES as s}
          <button class="type-tab" class:active={fStatus === s} on:click={() => fStatus = s}>
            {s === 'want' ? 'Хочу' : s === 'in_progress' ? 'Читаю/смотрю' : 'Готово'}
          </button>
        {/each}
      </div>
    </div>

    <div class="form-field">
      <label class="label" for="m-genre">Жанр (необязательно)</label>
      <input id="m-genre" type="text" bind:value={fGenre} placeholder="Фантастика, Триллер..." />
    </div>

    {#if fType === 'book'}
      <div class="form-row">
        <div class="form-field">
          <label class="label" for="m-pages">Всего страниц</label>
          <input id="m-pages" type="number" bind:value={fTotalPages} placeholder="300" inputmode="numeric" />
        </div>
        {#if fStatus === 'in_progress'}
          <div class="form-field">
            <label class="label" for="m-cur-page">Текущая стр.</label>
            <input id="m-cur-page" type="number" bind:value={fCurrentPage} placeholder="42" inputmode="numeric" />
          </div>
        {/if}
      </div>
    {/if}

    {#if fType === 'series'}
      <!-- Сезоны + "вышел полностью" в одну строку -->
      <div class="form-row" style="align-items:flex-end">
        <div class="form-field">
          <label class="label" for="m-seasons">Всего сезонов</label>
          <input id="m-seasons" type="number" bind:value={fSeasonsTotal} placeholder="3" inputmode="numeric" />
        </div>
        <div class="form-field" style="justify-content:flex-end;padding-bottom:0.125rem">
          <label class="toggle-label">
            <input type="checkbox" bind:checked={fSeriesFinished} />
            <span>Вышел полностью</span>
          </label>
        </div>
      </div>

      <!-- Серий в каждом сезоне — сезонные табы + input -->
      {#if parseInt(fSeasonsTotal) > 0}
        <div class="form-field">
          <label class="label">Серий в сезонах</label>
          <div class="season-tabs" style="margin-bottom:0.5rem">
            {#each { length: parseInt(fSeasonsTotal) } as _, si}
              <button class="season-tab-btn" class:active={fFormSeason === si} on:click={() => fFormSeason = si}>
                Сезон {si + 1}
                {#if fEpisodesPerSeason[si] > 0}
                  <span class="season-tab-count">{fEpisodesPerSeason[si]}</span>
                {/if}
              </button>
            {/each}
          </div>
          <input
            type="number" inputmode="numeric" placeholder="Сколько серий в сезоне {fFormSeason + 1}?"
            value={fEpisodesPerSeason[fFormSeason] || ''}
            on:input={e => {
              const v = parseInt(e.currentTarget.value)
              fEpisodesPerSeason[fFormSeason] = isNaN(v) ? 0 : v
              fEpisodesPerSeason = [...fEpisodesPerSeason]
            }}
          />
        </div>

        {#if fStatus === 'done'}
          <div class="form-field">
            <label class="label">Оценки по сезонам</label>
            {#each { length: parseInt(fSeasonsTotal) } as _, idx}
              <div class="season-rating-row">
                <span class="season-rating-label">Сезон {idx + 1}</span>
                <StarRating value={fSeasonRatings[idx] ?? 0} on:change={e => setSeasonRating(idx, e.detail)} />
              </div>
            {/each}
          </div>
        {/if}
      {/if}
    {/if}

    {#if fStatus === 'done'}
      <div class="form-field">
        <label class="label">Оценка</label>
        <StarRating value={fRating} on:change={e => fRating = e.detail} />
      </div>
    {/if}

    <div class="form-field">
      <label class="label" for="m-notes">Заметки</label>
      <textarea id="m-notes" bind:value={fNotes} rows="2" placeholder="Впечатления, рекомендации..." />
    </div>

    <button class="btn-primary" on:click={save} disabled={saving || !fTitle.trim()}>
      {saving ? 'Сохраняю...' : 'Сохранить'}
    </button>
  </div>
</Modal>

<style>
  .page-shell { max-width: 480px; margin: 0 auto; padding: 0 1.375rem 6rem; }

  .page-header { display: flex; align-items: center; justify-content: space-between; padding: 1rem 0 0.75rem; }

  .add-btn {
    background: var(--color-accent); color: white; border: none;
    border-radius: 0.875rem; padding: 0.5rem 1rem; font-size: 0.9375rem; cursor: pointer;
  }

  .status-tabs { display: flex; gap: 0.25rem; }
  .status-tab {
    flex: 1; padding: 0.5rem 0.25rem; border: 1px solid var(--color-border);
    border-radius: 0.75rem; background: var(--color-card); font-size: 0.75rem;
    color: var(--color-muted); cursor: pointer; text-align: center;
    -webkit-tap-highlight-color: transparent; transition: all 0.15s;
    display: flex; align-items: center; justify-content: center; gap: 0.25rem;
  }
  .status-tab.active { background: var(--color-accent); border-color: var(--color-accent); color: white; }

  .count {
    font-family: "JetBrains Mono", monospace; font-size: 0.6875rem;
    background: rgba(255,255,255,0.25); border-radius: 0.375rem; padding: 0 0.25rem;
  }
  .status-tab:not(.active) .count { background: var(--color-bg); color: var(--color-accent); }

  .type-filter-row { display: flex; gap: 0.375rem; flex-wrap: wrap; margin-top: 0.625rem; }
  .filter-chip {
    padding: 0.25rem 0.625rem; border: 1px solid var(--color-border); border-radius: 1rem;
    background: var(--color-card); font-size: 0.75rem; color: var(--color-muted);
    cursor: pointer; -webkit-tap-highlight-color: transparent; transition: all 0.15s;
  }
  .filter-chip.active { background: var(--color-accent); border-color: var(--color-accent); color: white; }

  .item-list { display: flex; flex-direction: column; gap: 0.625rem; }

  .item-card {
    background: var(--color-card); border: 1px solid var(--color-border);
    border-radius: 1rem; padding: 0.875rem 1rem; cursor: pointer;
    -webkit-tap-highlight-color: transparent; transition: opacity 0.3s, transform 0.3s;
  }
  .item-card:active { opacity: 0.8; }
  .item-card.moving { opacity: 0; transform: translateX(30px); pointer-events: none; }

  .item-top { display: flex; align-items: flex-start; gap: 0.5rem; margin-bottom: 0.25rem; cursor: pointer; -webkit-tap-highlight-color: transparent; }
  .item-info { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .item-badges { display: flex; align-items: center; gap: 0.375rem; }
  .item-type-badge { font-size: 0.6875rem; color: var(--color-accent); text-transform: uppercase; letter-spacing: 0.05em; }
  .finished-badge { font-size: 0.6875rem; color: var(--color-muted); border: 1px solid var(--color-border); border-radius: 0.375rem; padding: 0 0.25rem; }
  .item-title { font-size: 0.9375rem; font-weight: 500; }
  .item-genre { font-size: 0.75rem; color: var(--color-muted); }
  .item-rating { font-size: 0.875rem; color: var(--color-accent); letter-spacing: 1px; margin: 0.25rem 0; }
  .item-notes { font-size: 0.8125rem; color: var(--color-muted); margin: 0.25rem 0 0; }

  /* Book progress */
  .progress-row { display: flex; align-items: center; gap: 0.5rem; margin: 0.375rem 0 0.125rem; }
  .progress-bar { flex: 1; height: 3px; background: var(--color-border); border-radius: 2px; overflow: hidden; }
  .progress-fill { height: 100%; background: var(--color-accent); border-radius: 2px; transition: width 0.3s; }
  .progress-label { font-size: 0.75rem; color: var(--color-muted); white-space: nowrap; }
  .page-tappable { cursor: pointer; text-decoration: underline dotted; color: var(--color-accent); }
  .page-inline-input {
    width: 4rem; font-size: 0.75rem; padding: 0.1rem 0.25rem;
    border: 1px solid var(--color-accent); border-radius: 0.25rem;
    background: var(--color-card); color: var(--color-text); text-align: right; -moz-appearance: textfield;
  }
  .page-inline-input::-webkit-outer-spin-button,
  .page-inline-input::-webkit-inner-spin-button { -webkit-appearance: none; margin: 0; }

  /* Timer */
  .timer-row { display: flex; align-items: center; gap: 0.5rem; margin: 0.25rem 0; }
  .timer-btn {
    width: 1.75rem; height: 1.75rem; border-radius: 50%; border: 1.5px solid var(--color-border);
    background: none; color: var(--color-muted); cursor: pointer; font-size: 0.625rem;
    display: flex; align-items: center; justify-content: center; transition: all 0.15s;
    -webkit-tap-highlight-color: transparent;
  }
  .timer-btn.active { background: var(--color-accent); border-color: var(--color-accent); color: white; }
  .timer-display { font-family: "JetBrains Mono", monospace; font-size: 0.875rem; color: var(--color-accent); font-weight: 500; }
  .reading-total { font-size: 0.75rem; color: var(--color-muted); }

  /* Series */
  .series-header {
    display: flex; align-items: center; justify-content: space-between;
    margin: 0.375rem 0 0.25rem; cursor: pointer; -webkit-tap-highlight-color: transparent;
  }
  .series-progress-text { font-size: 0.8125rem; color: var(--color-accent); font-family: "JetBrains Mono", monospace; }
  .series-not-started { color: var(--color-muted); font-family: inherit; }
  .expand-chevron { font-size: 1.125rem; color: var(--color-muted); transition: transform 0.2s; line-height: 1; }
  .expand-chevron.open { transform: rotate(180deg); }

  /* Season tabs */
  .season-tabs { display: flex; gap: 0.375rem; flex-wrap: wrap; margin: 0.25rem 0 0.5rem; }
  .season-tab-btn {
    padding: 0.25rem 0.625rem; border: 1px solid var(--color-border); border-radius: 0.5rem;
    background: none; font-size: 0.75rem; color: var(--color-muted); cursor: pointer;
    transition: all 0.15s; -webkit-tap-highlight-color: transparent;
    display: flex; align-items: center; gap: 0.25rem;
  }
  .season-tab-btn.active { background: var(--color-accent); border-color: var(--color-accent); color: white; }
  .season-tab-count { font-size: 0.625rem; opacity: 0.8; }

  /* Episode rows — 3 states */
  .eps-list { display: flex; flex-direction: column; gap: 0.25rem; margin: 0.125rem 0 0.375rem; }

  .ep-row {
    display: flex; align-items: center; justify-content: space-between;
    width: 100%; padding: 0.5rem 0.75rem;
    border-radius: 0.75rem; border: 1px solid var(--color-border);
    background: none; cursor: pointer; transition: all 0.12s;
    -webkit-tap-highlight-color: transparent;
  }

  .ep-watched { background: var(--color-card); opacity: 0.55; }
  .ep-current { background: var(--color-accent); border-color: var(--color-accent); color: white; }
  .ep-remaining { background: none; }

  .ep-label { font-size: 0.8125rem; }
  .ep-watched .ep-label { color: var(--color-muted); }
  .ep-current .ep-label { color: white; font-weight: 500; }
  .ep-remaining .ep-label { color: var(--color-text); }

  .ep-toggle {
    width: 1.125rem; height: 1.125rem; border-radius: 50%; flex-shrink: 0;
    border: 2px solid currentColor;
  }
  .ep-toggle-watched { background: var(--color-muted); border-color: var(--color-muted); }
  .ep-toggle-current { background: white; border-color: white; }
  .ep-toggle-remaining { background: none; border-color: var(--color-border); }

  /* Episode count setup */
  .eps-setup { display: flex; align-items: center; gap: 0.625rem; margin: 0.25rem 0; }
  .eps-setup-label { font-size: 0.8125rem; color: var(--color-muted); }
  .eps-count-input {
    width: 4.5rem; font-size: 0.8125rem; padding: 0.25rem 0.5rem;
    border: 1px solid var(--color-accent); border-radius: 0.375rem;
    background: var(--color-card); color: var(--color-text); text-align: center;
    -moz-appearance: textfield;
  }
  .eps-count-input::-webkit-outer-spin-button,
  .eps-count-input::-webkit-inner-spin-button { -webkit-appearance: none; margin: 0; }

  /* Season ratings */
  .season-ratings-row { display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; margin: 0.1rem 0; }
  .season-rating-chip { font-size: 0.6875rem; color: var(--color-muted); font-family: "JetBrains Mono", monospace; }

  .item-actions { margin-top: 0.625rem; display: flex; gap: 0.5rem; }
  .action-btn {
    padding: 0.375rem 0.75rem; border: 1px solid var(--color-accent);
    border-radius: 0.625rem; background: none; color: var(--color-accent);
    font-size: 0.8125rem; cursor: pointer; -webkit-tap-highlight-color: transparent;
  }

  .del-btn { background: none; border: none; color: var(--color-muted); font-size: 1.25rem; cursor: pointer; padding: 0 0.25rem; line-height: 1; }

  /* Form */
  .type-tabs { display: flex; background: var(--color-card); border-radius: 0.875rem; padding: 0.25rem; gap: 0.25rem; border: 1px solid var(--color-border); }
  .type-tab { flex: 1; padding: 0.5rem; border: none; border-radius: 0.625rem; font-size: 0.8125rem; background: none; color: var(--color-muted); cursor: pointer; transition: all 0.15s; }
  .type-tab.active { background: var(--color-accent); color: white; }

  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; flex: 1; }
  .form-row { display: flex; gap: 0.75rem; }

  .toggle-row { flex-direction: row; align-items: center; }
  .toggle-label { display: flex; align-items: center; gap: 0.5rem; font-size: 0.875rem; color: var(--color-text); cursor: pointer; }

  .season-rating-row { display: flex; align-items: center; gap: 0.5rem; margin: 0.1rem 0; }
  .season-rating-label { font-size: 0.8125rem; color: var(--color-muted); min-width: 5rem; }

  .empty-state { padding: 2rem; text-align: center; color: var(--color-muted); background: var(--color-card); border-radius: 1.25rem; border: 1px dashed var(--color-border); }

  .skeleton { border-radius: 1.25rem; background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .mt-3 { margin-top: 0.75rem; }
  .mt-4 { margin-top: 1rem; }
</style>
