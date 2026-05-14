<script lang="ts">
  import { onMount } from 'svelte'
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

  // Form
  let fTitle = ''
  let fType: MediaType = 'book'
  let fGenre = ''
  let fStatus: MediaStatus = 'want'
  let fRating = 0
  let fNotes = ''
  let fTotalPages = ''
  let fCurrentPage = ''
  let fSeasonsTotal = ''
  let fCurrentSeason = ''
  let fCurrentEpisode = ''
  let saving = false

  const typeLabel: Record<MediaType, string> = { book: 'Книга', film: 'Фильм', series: 'Сериал' }
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

  function filtered(status: MediaStatus) {
    return items.filter(i => i.status === status)
  }

  function openAdd(status: MediaStatus = activeStatus === 'in_progress' ? 'want' : activeStatus) {
    editItem = null
    fTitle = ''; fType = 'book'; fGenre = ''; fStatus = status
    fRating = 0; fNotes = ''
    fTotalPages = ''; fCurrentPage = ''
    fSeasonsTotal = ''; fCurrentSeason = ''; fCurrentEpisode = ''
    showModal = true
  }

  function openEdit(item: MediaItem) {
    editItem = item
    fTitle = item.title; fType = item.type; fGenre = item.genre ?? ''
    fStatus = item.status; fRating = item.rating ?? 0; fNotes = item.notes ?? ''
    fTotalPages = item.total_pages?.toString() ?? ''
    fCurrentPage = item.current_page?.toString() ?? ''
    fSeasonsTotal = item.seasons_total?.toString() ?? ''
    fCurrentSeason = item.current_season?.toString() ?? ''
    fCurrentEpisode = item.current_episode?.toString() ?? ''
    showModal = true
  }

  async function save() {
    if (!$user || !fTitle.trim()) return
    saving = true
    const payload = {
      user_id: $user.id,
      title: fTitle.trim(),
      type: fType,
      genre: fGenre || null,
      status: fStatus,
      rating: fRating || null,
      notes: fNotes || null,
      total_pages: fTotalPages ? parseInt(fTotalPages) : null,
      current_page: fCurrentPage ? parseInt(fCurrentPage) : null,
      seasons_total: fSeasonsTotal ? parseInt(fSeasonsTotal) : null,
      current_season: fCurrentSeason ? parseInt(fCurrentSeason) : null,
      current_episode: fCurrentEpisode ? parseInt(fCurrentEpisode) : null,
      is_finished: fStatus === 'done',
      started_at: fStatus !== 'want' && !editItem?.started_at ? new Date().toISOString() : editItem?.started_at ?? null,
      finished_at: fStatus === 'done' && !editItem?.finished_at ? new Date().toISOString() : editItem?.finished_at ?? null,
    }
    if (editItem) {
      const { data } = await supabase.from('media_items').update(payload).eq('id', editItem.id).select().single()
      if (data) items = items.map(i => i.id === editItem!.id ? data : i)
    } else {
      const { data } = await supabase.from('media_items').insert(payload).select().single()
      if (data) items = [data, ...items]
    }
    showModal = false
    saving = false
  }

  async function deleteItem(id: string) {
    await supabase.from('media_items').delete().eq('id', id)
    items = items.filter(i => i.id !== id)
  }

  async function moveStatus(item: MediaItem, status: MediaStatus) {
    const updates: Partial<MediaItem> = { status, is_finished: status === 'done' }
    if (status !== 'want' && !item.started_at) updates.started_at = new Date().toISOString()
    if (status === 'done' && !item.finished_at) updates.finished_at = new Date().toISOString()
    await supabase.from('media_items').update(updates).eq('id', item.id)
    items = items.map(i => i.id === item.id ? { ...i, ...updates } : i)
  }

  function bookProgress(item: MediaItem): number | null {
    if (!item.current_page || !item.total_pages) return null
    return Math.round((item.current_page / item.total_pages) * 100)
  }

  onMount(load)
</script>

<div class="page-shell">
  <header class="page-header">
    <h1 class="section-title">Медиа</h1>
    <button class="add-btn" on:click={() => openAdd('want')}>+ Добавить</button>
  </header>

  <!-- Status tabs -->
  <div class="status-tabs">
    {#each ALL_STATUSES as s}
      <button
        class="status-tab"
        class:active={activeStatus === s}
        on:click={() => activeStatus = s}
      >
        {statusLabel[s]}
        {#if filtered(s).length > 0}
          <span class="count">{filtered(s).length}</span>
        {/if}
      </button>
    {/each}
  </div>

  {#if loading}
    <div class="skeleton mt-4" style="height:10rem" />
  {:else if filtered(activeStatus).length === 0}
    <div class="empty-state mt-4">
      {activeStatus === 'want' ? 'Ничего не запланировано' :
       activeStatus === 'in_progress' ? 'Ничего в процессе' : 'Ещё ничего не закончено'}
    </div>
  {:else}
    <div class="item-list mt-3">
      {#each filtered(activeStatus) as item}
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="item-card" on:click={() => openEdit(item)}>
          <div class="item-top">
            <div class="item-info">
              <span class="item-type-badge">{typeLabel[item.type]}</span>
              <span class="item-title">{item.title}</span>
              {#if item.genre}<span class="item-genre">{item.genre}</span>{/if}
            </div>
            <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
            <button class="del-btn" on:click|stopPropagation={() => deleteItem(item.id)}>×</button>
          </div>

          <!-- Book progress -->
          {#if item.type === 'book' && item.status === 'in_progress' && item.current_page}
            <div class="progress-row">
              {#if item.total_pages}
                <div class="progress-bar">
                  <div class="progress-fill" style="width: {bookProgress(item)}%" />
                </div>
                <span class="progress-label">{item.current_page} / {item.total_pages} стр.</span>
              {:else}
                <span class="progress-label">стр. {item.current_page}</span>
              {/if}
            </div>
          {/if}

          <!-- Series progress -->
          {#if item.type === 'series' && item.status === 'in_progress' && (item.current_season || item.current_episode)}
            <div class="series-progress">
              {#if item.current_season}С{item.current_season}{item.seasons_total ? '/' + item.seasons_total : ''}{/if}{#if item.current_episode} · Серия {item.current_episode}{/if}
            </div>
          {/if}

          {#if item.rating}
            <div class="item-rating">{'★'.repeat(item.rating)}{'☆'.repeat(5 - item.rating)}</div>
          {/if}
          {#if item.notes}
            <p class="item-notes">{item.notes}</p>
          {/if}
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
          <button class="type-tab" class:active={fType === t} on:click={() => fType = t}>
            {typeLabel[t]}
          </button>
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

    <!-- Book fields -->
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

    <!-- Series fields -->
    {#if fType === 'series'}
      <div class="form-row">
        <div class="form-field">
          <label class="label" for="m-seasons">Всего сезонов</label>
          <input id="m-seasons" type="number" bind:value={fSeasonsTotal} placeholder="3" inputmode="numeric" />
        </div>
      </div>
      {#if fStatus === 'in_progress'}
        <div class="form-row">
          <div class="form-field">
            <label class="label" for="m-cur-s">Сезон</label>
            <input id="m-cur-s" type="number" bind:value={fCurrentSeason} placeholder="1" inputmode="numeric" />
          </div>
          <div class="form-field">
            <label class="label" for="m-cur-e">Серия</label>
            <input id="m-cur-e" type="number" bind:value={fCurrentEpisode} placeholder="5" inputmode="numeric" />
          </div>
        </div>
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
  .page-shell { max-width: 480px; margin: 0 auto; padding: 0 1rem 6rem; }

  .page-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 1rem 0 0.75rem;
  }

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
    font-family: "JetBrains Mono", monospace;
    font-size: 0.6875rem;
    background: rgba(255,255,255,0.25);
    border-radius: 0.375rem;
    padding: 0 0.25rem;
  }
  .status-tab:not(.active) .count { background: var(--color-bg); color: var(--color-accent); }

  .item-list { display: flex; flex-direction: column; gap: 0.625rem; }

  .item-card {
    background: var(--color-card); border: 1px solid var(--color-border);
    border-radius: 1rem; padding: 0.875rem 1rem; cursor: pointer;
    -webkit-tap-highlight-color: transparent; transition: opacity 0.15s;
  }
  .item-card:active { opacity: 0.8; }

  .item-top { display: flex; align-items: flex-start; gap: 0.5rem; margin-bottom: 0.25rem; }
  .item-info { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .item-type-badge {
    font-size: 0.6875rem; color: var(--color-accent);
    text-transform: uppercase; letter-spacing: 0.05em;
  }
  .item-title { font-size: 0.9375rem; font-weight: 500; }
  .item-genre { font-size: 0.75rem; color: var(--color-muted); }
  .item-rating { font-size: 0.875rem; color: var(--color-accent); letter-spacing: 1px; margin: 0.25rem 0; }
  .item-notes { font-size: 0.8125rem; color: var(--color-muted); margin: 0.25rem 0 0; }

  .progress-row {
    display: flex; align-items: center; gap: 0.5rem;
    margin: 0.375rem 0;
  }
  .progress-bar {
    flex: 1; height: 3px; background: var(--color-border); border-radius: 2px; overflow: hidden;
  }
  .progress-fill {
    height: 100%; background: var(--color-accent); border-radius: 2px;
    transition: width 0.3s;
  }
  .progress-label { font-size: 0.75rem; color: var(--color-muted); white-space: nowrap; }

  .series-progress {
    font-size: 0.8125rem; color: var(--color-accent);
    margin: 0.25rem 0;
    font-family: "JetBrains Mono", monospace;
  }

  .item-actions { margin-top: 0.625rem; display: flex; gap: 0.5rem; }
  .action-btn {
    padding: 0.375rem 0.75rem; border: 1px solid var(--color-accent);
    border-radius: 0.625rem; background: none; color: var(--color-accent);
    font-size: 0.8125rem; cursor: pointer; -webkit-tap-highlight-color: transparent;
  }

  .del-btn { background: none; border: none; color: var(--color-muted); font-size: 1.25rem; cursor: pointer; padding: 0 0.25rem; line-height: 1; }

  .type-tabs { display: flex; background: var(--color-card); border-radius: 0.875rem; padding: 0.25rem; gap: 0.25rem; border: 1px solid var(--color-border); }
  .type-tab { flex: 1; padding: 0.5rem; border: none; border-radius: 0.625rem; font-size: 0.8125rem; background: none; color: var(--color-muted); cursor: pointer; transition: all 0.15s; }
  .type-tab.active { background: var(--color-accent); color: white; }

  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; flex: 1; }
  .form-row { display: flex; gap: 0.75rem; }

  .empty-state { padding: 2rem; text-align: center; color: var(--color-muted); background: var(--color-card); border-radius: 1.25rem; border: 1px dashed var(--color-border); }

  .skeleton { border-radius: 1.25rem; background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .mt-3 { margin-top: 0.75rem; }
  .mt-4 { margin-top: 1rem; }
</style>
