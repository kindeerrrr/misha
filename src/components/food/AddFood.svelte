<script lang="ts">
  import { createEventDispatcher, onDestroy } from 'svelte'
  import type { FoodCandidate, RawFoodEntry as RawEntry } from '../../lib/food-types'

  // ── Props ─────────────────────────────────────────────────────────────────
  export let mealLabel:       string     = 'приём пищи'
  export let recentEntries:   RawEntry[] = []
  export let frequentEntries: RawEntry[] = []
  export let fsWorker:        string     = ''

  type Tab = 'search' | 'recent' | 'frequent' | 'saved'

  const TABS: Array<{id: Tab; label: string}> = [
    { id: 'search',   label: 'Еда'         },
    { id: 'recent',   label: 'Недавно'     },
    { id: 'frequent', label: 'Часто'       },
    { id: 'saved',    label: 'Сохранённое' },
  ]

  // ── State ─────────────────────────────────────────────────────────────────
  let tab: Tab      = 'search'
  let query         = ''
  let suggestions:  FoodCandidate[] = []
  let fsSearching   = false
  let fsTimer:      ReturnType<typeof setTimeout> | null = null

  const dispatch = createEventDispatcher<{
    pick:    FoodCandidate
    barcode: void
    close:   void
  }>()

  // ── Per-100g helpers (for quick picks) ───────────────────────────────────
  function cal100(e: RawEntry): number | null {
    return e.amount ? Math.round((e.calories ?? 0) / e.amount * 100) : null
  }
  function prot100(e: RawEntry): number | null {
    return e.amount && e.protein  != null ? Math.round(e.protein  / e.amount * 100 * 10) / 10 : null
  }
  function fat100(e: RawEntry): number | null {
    return e.amount && e.fat      != null ? Math.round(e.fat      / e.amount * 100 * 10) / 10 : null
  }
  function carb100(e: RawEntry): number | null {
    return e.amount && e.carbs    != null ? Math.round(e.carbs    / e.amount * 100 * 10) / 10 : null
  }

  function entryToCandidate(e: RawEntry): FoodCandidate {
    return {
      id:                `quick-${e.food_name}`,
      name:              e.food_name,
      brand:             null,
      calories_per_100g: cal100(e),
      protein_per_100g:  prot100(e),
      fat_per_100g:      fat100(e),
      carbs_per_100g:    carb100(e),
      source:            'local',
    }
  }

  // ── Search logic ──────────────────────────────────────────────────────────
  function localSuggestions(q: string): FoodCandidate[] {
    const all = [...recentEntries, ...frequentEntries]
    const seen = new Set<string>()
    return all
      .filter(e => e.food_name.toLowerCase().includes(q))
      .filter(e => { const k = e.food_name.toLowerCase(); if (seen.has(k)) return false; seen.add(k); return true })
      .slice(0, 5)
      .map(entryToCandidate)
  }

  async function searchFS(q: string): Promise<FoodCandidate[]> {
    if (!fsWorker) return []
    try {
      fsSearching = true
      const res  = await fetch(`${fsWorker}/search?q=${encodeURIComponent(q)}`)
      if (!res.ok) return []
      const data = await res.json()
      return (data.results ?? []).map((f: {
        id: string; name: string; brand: string | null;
        calories_per_100g?: number; protein_per_100g?: number;
        fat_per_100g?: number; carbs_per_100g?: number;
      }) => ({
        id:                `fs-${f.id}`,
        name:              f.brand ? `${f.name} (${f.brand})` : f.name,
        brand:             f.brand ?? null,
        calories_per_100g: f.calories_per_100g ?? null,
        protein_per_100g:  f.protein_per_100g  ?? null,
        fat_per_100g:      f.fat_per_100g      ?? null,
        carbs_per_100g:    f.carbs_per_100g    ?? null,
        source:            'fatsecret' as const,
      }))
    } catch { return [] }
    finally   { fsSearching = false }
  }

  function onInput() {
    const q = query.trim().toLowerCase()
    if (q.length < 1) { suggestions = []; return }
    suggestions = localSuggestions(q)
    if (fsTimer) clearTimeout(fsTimer)
    if (fsWorker) {
      fsTimer = setTimeout(async () => {
        const fsSuggs  = await searchFS(q)
        const existing = new Set(suggestions.map(s => s.name.toLowerCase()))
        suggestions    = [...suggestions, ...fsSuggs.filter(s => !existing.has(s.name.toLowerCase()))].slice(0, 12)
      }, 400)
    }
  }

  function fmt(n: number | null): string {
    return n != null ? Math.round(n).toString() : '—'
  }

  onDestroy(() => { if (fsTimer) clearTimeout(fsTimer) })
</script>

<div class="add-food-screen">
  <!-- ── Header ── -->
  <header class="add-header">
    <div class="add-title-block">
      <span class="add-subtitle">Добавить в</span>
      <span class="add-meal-name">{mealLabel}</span>
    </div>
    <button class="cancel-btn" on:click={() => dispatch('close')}>Отмена</button>
  </header>

  <!-- ── Search bar ── -->
  <div class="search-wrap">
    <div class="search-box">
      <svg class="search-ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16">
        <circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>
      </svg>
      <input
        class="search-input"
        type="search"
        inputmode="search"
        placeholder="Название продукта…"
        bind:value={query}
        on:input={onInput}
        autocomplete="off"
        autofocus
      />
      {#if fsSearching}
        <span class="search-spin">⟳</span>
      {:else if query}
        <button class="search-clear" on:click={() => { query = ''; suggestions = [] }}>✕</button>
      {/if}
    </div>
  </div>

  <!-- ── Tabs ── -->
  <div class="tabs">
    {#each TABS as t}
      <button class="tab-btn" class:active={tab === t.id} on:click={() => tab = t.id}>{t.label}</button>
    {/each}
  </div>

  <!-- ── Content ── -->
  <div class="tab-content">

    <!-- Еда tab -->
    {#if tab === 'search'}
      {#if suggestions.length === 0 && query.length === 0}
        <div class="empty-hint">
          <p>Введите название продукта</p>
          <p class="empty-sub">или отсканируйте штрихкод</p>
        </div>
      {:else if suggestions.length === 0 && query.length > 0 && !fsSearching}
        <div class="empty-hint">
          <p>Ничего не найдено</p>
          <p class="empty-sub">Попробуйте другое название</p>
        </div>
      {:else}
        <div class="result-list">
          {#each suggestions as s}
            <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
            <div class="result-row" on:click={() => dispatch('pick', s)}>
              <div class="result-info">
                <span class="result-name">{s.name}</span>
                {#if s.calories_per_100g}
                  <span class="result-meta">{s.calories_per_100g} ккал · 100г</span>
                {/if}
              </div>
              <div class="result-right">
                {#if s.source === 'fatsecret'}
                  <span class="fs-badge">FS</span>
                {/if}
                <svg viewBox="0 0 24 24" fill="none" stroke="var(--color-muted)" stroke-width="1.5" width="16" height="16">
                  <path d="M9 18l6-6-6-6"/>
                </svg>
              </div>
            </div>
          {/each}
        </div>
      {/if}

    <!-- Недавно tab -->
    {:else if tab === 'recent'}
      {#if recentEntries.length === 0}
        <div class="empty-hint"><p>Нет истории</p><p class="empty-sub">Добавьте первый продукт</p></div>
      {:else}
        <div class="result-list">
          {#each recentEntries as e}
            <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
            <div class="result-row" on:click={() => dispatch('pick', entryToCandidate(e))}>
              <div class="result-info">
                <span class="result-name">{e.food_name}</span>
                <span class="result-meta">
                  {e.amount}{e.unit}{e.calories != null ? ` · ${fmt(e.calories)} ккал` : ''}
                  {#if cal100(e) != null} · {cal100(e)} ккал/100г{/if}
                </span>
              </div>
              <svg viewBox="0 0 24 24" fill="none" stroke="var(--color-muted)" stroke-width="1.5" width="16" height="16">
                <path d="M9 18l6-6-6-6"/>
              </svg>
            </div>
          {/each}
        </div>
      {/if}

    <!-- Часто tab -->
    {:else if tab === 'frequent'}
      {#if frequentEntries.length === 0}
        <div class="empty-hint"><p>Нет истории</p><p class="empty-sub">Добавляйте продукты, и они появятся здесь</p></div>
      {:else}
        <div class="result-list">
          {#each frequentEntries as e}
            <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
            <div class="result-row" on:click={() => dispatch('pick', entryToCandidate(e))}>
              <div class="result-info">
                <span class="result-name">{e.food_name}</span>
                <span class="result-meta">
                  {e.amount}{e.unit}{e.calories != null ? ` · ${fmt(e.calories)} ккал` : ''}
                  {#if cal100(e) != null} · {cal100(e)} ккал/100г{/if}
                </span>
              </div>
              <svg viewBox="0 0 24 24" fill="none" stroke="var(--color-muted)" stroke-width="1.5" width="16" height="16">
                <path d="M9 18l6-6-6-6"/>
              </svg>
            </div>
          {/each}
        </div>
      {/if}

    <!-- Сохранённое tab -->
    {:else}
      <div class="empty-hint">
        <p>Скоро</p>
        <p class="empty-sub">Сохранение блюд появится в следующей версии</p>
      </div>
    {/if}

  </div>

  <!-- ── Bottom action bar ── -->
  <div class="bottom-bar">
    <button class="action-btn" disabled title="Скоро">
      <span class="action-ico">📸</span>
      <span class="action-lbl">Фото</span>
    </button>
    <button class="action-btn" disabled title="Скоро">
      <span class="action-ico">✨</span>
      <span class="action-lbl">Голос</span>
    </button>
    <button class="action-btn" on:click={() => dispatch('barcode')}>
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" width="22" height="22">
        <rect x="2"  y="2"  width="5" height="5" rx="1"/>
        <rect x="17" y="2"  width="5" height="5" rx="1"/>
        <rect x="2"  y="17" width="5" height="5" rx="1"/>
        <line x1="17" y1="17" x2="22" y2="17"/>
        <line x1="17" y1="17" x2="17" y2="22"/>
        <line x1="2"  y1="9"  x2="2"  y2="9"/>
        <line x1="7"  y1="9"  x2="9"  y2="9"/>
        <line x1="9"  y1="2"  x2="9"  y2="7"/>
        <line x1="12" y1="2"  x2="12" y2="5"/>
        <line x1="12" y1="7"  x2="12" y2="9"/>
        <line x1="15" y1="7"  x2="17" y2="7"/>
        <line x1="12" y1="12" x2="22" y2="12"/>
        <line x1="2"  y1="12" x2="9"  y2="12"/>
        <line x1="2"  y1="15" x2="2"  y2="17"/>
        <line x1="5"  y1="15" x2="7"  y2="15"/>
      </svg>
      <span class="action-lbl">Штрихкод</span>
    </button>
  </div>
</div>

<style>
  .add-food-screen {
    position: fixed;
    inset: 0;
    background: var(--color-bg);
    z-index: 300;
    display: flex;
    flex-direction: column;
    animation: slideUp 0.28s cubic-bezier(0.32, 0.72, 0, 1);
  }
  @keyframes slideUp {
    from { transform: translateY(100%); }
    to   { transform: translateY(0); }
  }

  /* ── Header ── */
  .add-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.875rem 1.125rem 0.625rem;
    padding-top: calc(0.875rem + env(safe-area-inset-top));
    background: var(--color-card);
    border-bottom: 1px solid var(--color-border);
    flex-shrink: 0;
  }
  .add-title-block { display: flex; flex-direction: column; gap: 1px; }
  .add-subtitle { font-size: 0.72rem; color: var(--color-muted); text-transform: uppercase; letter-spacing: 0.05em; }
  .add-meal-name { font-size: 1.0625rem; font-weight: 600; color: var(--color-text); }
  .cancel-btn {
    background: none; border: none;
    color: var(--color-accent); font-size: 1rem; font-family: inherit;
    cursor: pointer; padding: 0.25rem 0;
    -webkit-tap-highlight-color: transparent;
  }

  /* ── Search ── */
  .search-wrap { padding: 0.75rem 1rem 0.5rem; flex-shrink: 0; }
  .search-box {
    display: flex; align-items: center; gap: 0.5rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem; padding: 0.625rem 0.875rem;
  }
  .search-ico { flex-shrink: 0; color: var(--color-muted); }
  .search-input {
    flex: 1; background: none; border: none;
    color: var(--color-text); font-size: 1rem; font-family: inherit;
    outline: none; min-width: 0;
  }
  .search-input::placeholder { color: var(--color-muted); }
  .search-spin { color: var(--color-muted); animation: spin 1s linear infinite; display: inline-block; font-size: 1.1rem; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .search-clear {
    background: none; border: none; color: var(--color-muted); cursor: pointer;
    font-size: 0.875rem; padding: 0; line-height: 1;
    -webkit-tap-highlight-color: transparent;
  }

  /* ── Tabs ── */
  .tabs {
    display: flex; border-bottom: 1px solid var(--color-border);
    flex-shrink: 0; background: var(--color-card);
    overflow-x: auto; scrollbar-width: none;
  }
  .tabs::-webkit-scrollbar { display: none; }
  .tab-btn {
    flex-shrink: 0; padding: 0.625rem 1rem;
    background: none; border: none; border-bottom: 2px solid transparent;
    font-size: 0.875rem; font-family: inherit; color: var(--color-muted);
    cursor: pointer; white-space: nowrap; margin-bottom: -1px;
    -webkit-tap-highlight-color: transparent; transition: all 0.15s;
  }
  .tab-btn.active {
    color: var(--color-accent);
    border-bottom-color: var(--color-accent);
    font-weight: 600;
  }

  /* ── Tab content ── */
  .tab-content {
    flex: 1; overflow-y: auto;
    -webkit-overflow-scrolling: touch;
  }

  /* ── Result list ── */
  .result-list { display: flex; flex-direction: column; }
  .result-row {
    display: flex; align-items: center; gap: 0.75rem;
    padding: 0.875rem 1rem;
    border-bottom: 1px solid var(--color-border);
    cursor: pointer; -webkit-tap-highlight-color: transparent;
    transition: background 0.1s;
  }
  .result-row:last-child { border-bottom: none; }
  .result-row:active { background: var(--color-card); }
  .result-info { flex: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .result-name { font-size: 0.9375rem; color: var(--color-text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .result-meta { font-size: 0.75rem; color: var(--color-muted); }
  .result-right { display: flex; align-items: center; gap: 0.375rem; flex-shrink: 0; }
  .fs-badge {
    font-size: 0.625rem; font-weight: 700;
    padding: 2px 5px; border-radius: 4px;
    background: #dbeafe; color: #1d4ed8;
    letter-spacing: 0.04em;
  }

  /* ── Empty state ── */
  .empty-hint {
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    padding: 3rem 1rem; gap: 0.375rem; text-align: center;
  }
  .empty-hint p { margin: 0; font-size: 0.9375rem; color: var(--color-muted); }
  .empty-sub { font-size: 0.8125rem !important; opacity: 0.7; }

  /* ── Bottom bar ── */
  .bottom-bar {
    display: flex; justify-content: space-around;
    padding: 0.875rem 1rem;
    padding-bottom: calc(0.875rem + env(safe-area-inset-bottom));
    background: var(--color-card);
    border-top: 1px solid var(--color-border);
    flex-shrink: 0;
  }
  .action-btn {
    display: flex; flex-direction: column; align-items: center; gap: 4px;
    background: none; border: none;
    color: var(--color-accent); font-family: inherit;
    cursor: pointer; padding: 0.375rem 1rem;
    border-radius: 0.75rem; transition: background 0.15s;
    -webkit-tap-highlight-color: transparent;
  }
  .action-btn:disabled { opacity: 0.4; cursor: default; }
  .action-btn:not(:disabled):active { background: var(--color-bg); }
  .action-ico { font-size: 1.375rem; line-height: 1; }
  .action-lbl { font-size: 0.6875rem; color: var(--color-muted); }
</style>
