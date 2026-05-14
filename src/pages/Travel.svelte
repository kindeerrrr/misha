<script lang="ts">
  /*
    SQL migration (run once in Supabase SQL editor):

    create table if not exists trips (
      id uuid primary key default gen_random_uuid(),
      user_id uuid references auth.users not null,
      title text not null,
      city text not null,
      country text,
      start_date date not null,
      end_date date,
      notes text,
      cover_emoji text default '✈️',
      created_at timestamptz default now()
    );
    alter table trips enable row level security;
    create policy "trips: own" on trips for all using (auth.uid() = user_id);

    create table if not exists trip_spots (
      id uuid primary key default gen_random_uuid(),
      user_id uuid references auth.users not null,
      trip_id uuid references trips on delete cascade not null,
      name text not null,
      category text not null default 'place',
      date date not null,
      start_time time,
      end_time time,
      address text,
      notes text,
      sort_order int default 0,
      created_at timestamptz default now()
    );
    alter table trip_spots enable row level security;
    create policy "trip_spots: own" on trip_spots for all using (auth.uid() = user_id);

    create table if not exists packing_bags (
      id uuid primary key default gen_random_uuid(),
      user_id uuid references auth.users not null,
      trip_id uuid references trips on delete cascade not null,
      name text not null,
      sort_order int default 0,
      created_at timestamptz default now()
    );
    alter table packing_bags enable row level security;
    create policy "packing_bags: own" on packing_bags for all using (auth.uid() = user_id);

    create table if not exists packing_items (
      id uuid primary key default gen_random_uuid(),
      user_id uuid references auth.users not null,
      trip_id uuid references trips on delete cascade not null,
      bag_id uuid references packing_bags on delete set null,
      name text not null,
      packed boolean default false,
      sort_order int default 0,
      created_at timestamptz default now()
    );
    alter table packing_items enable row level security;
    create policy "packing_items: own" on packing_items for all using (auth.uid() = user_id);

    create table if not exists trip_documents (
      id uuid primary key default gen_random_uuid(),
      user_id uuid references auth.users not null,
      trip_id uuid references trips on delete cascade not null,
      name text not null,
      file_url text not null,
      file_type text not null default 'photo',
      created_at timestamptz default now()
    );
    alter table trip_documents enable row level security;
    create policy "trip_documents: own" on trip_documents for all using (auth.uid() = user_id);
  */

  import { onMount } from 'svelte'
  import { supabase, today, uploadFile } from '../lib/supabase'
  import { user } from '../stores/user'
  import { icons } from '../lib/icons'
  import Modal from '../components/ui/Modal.svelte'
  import { showToast } from '../stores/toast'
  import type { Trip, TripSpot, PackingBag, PackingItem, TripDocument, SpotCategory } from '../lib/types'

  const todayDate = today()

  const RU_MONTHS = ['янв.','фев.','мар.','апр.','мая','июн.','июл.','авг.','сен.','окт.','ноя.','дек.']
  const RU_MONTHS_GEN = ['января','февраля','марта','апреля','мая','июня','июля','августа','сентября','октября','ноября','декабря']
  const RU_MONTH_LABELS = ['Январь','Февраль','Март','Апрель','Май','Июнь','Июль','Август','Сентябрь','Октябрь','Ноябрь','Декабрь']

  const SPOT_CATEGORIES: { id: SpotCategory; label: string; icon: string }[] = [
    { id: 'city',     label: 'Город',  icon: icons.map_pin },
    { id: 'place',    label: 'Место',  icon: icons.star },
    { id: 'food',     label: 'Еда',    icon: icons.bowl },
    { id: 'shopping', label: 'Шопинг', icon: icons.shopping_bag },
  ]

  const TRIP_EMOJIS = ['✈️','🌍','🏔️','🏖️','🗺️','🏛️','🌆','🚂','🚢','🧳']

  function fmt(d: string | null | undefined): string {
    if (!d) return ''
    const parts = d.split('-')
    if (parts.length < 3) return ''
    return `${parseInt(parts[2])} ${RU_MONTHS[parseInt(parts[1]) - 1]}`
  }

  function fmtLong(d: string | null | undefined): string {
    if (!d) return ''
    const parts = d.split('-')
    if (parts.length < 3) return ''
    return `${parseInt(parts[2])} ${RU_MONTHS_GEN[parseInt(parts[1]) - 1]} ${parts[0]}`
  }

  function tripDateRange(t: Trip): string {
    const s = fmt(t.start_date)
    if (!t.end_date) return s
    const eParts = t.end_date.split('-')
    const sParts = t.start_date.split('-')
    if (eParts[0] === sParts[0] && eParts[1] === sParts[1]) {
      return `${parseInt(sParts[2])}–${parseInt(eParts[2])} ${RU_MONTHS[parseInt(sParts[1]) - 1]} ${sParts[0]}`
    }
    return `${fmt(t.start_date)} – ${fmt(t.end_date)} ${eParts[0]}`
  }

  function monthKey(d: string): string { return d.slice(0, 7) }
  function monthLabel(key: string): string {
    const [y, m] = key.split('-')
    return `${RU_MONTH_LABELS[parseInt(m) - 1]} ${y}`
  }

  function groupByMonth(ts: Trip[]): { key: string; label: string; trips: Trip[] }[] {
    const map = new Map<string, Trip[]>()
    const sorted = [...ts].sort((a, b) => b.start_date.localeCompare(a.start_date))
    for (const t of sorted) {
      const k = monthKey(t.start_date)
      if (!map.has(k)) map.set(k, [])
      map.get(k)!.push(t)
    }
    return Array.from(map.entries()).map(([key, trips]) => ({ key, label: monthLabel(key), trips }))
  }

  function groupByDate(ss: TripSpot[]): { date: string; label: string; spots: TripSpot[] }[] {
    const map = new Map<string, TripSpot[]>()
    const sorted = [...ss].sort((a, b) => {
      if (a.date !== b.date) return a.date.localeCompare(b.date)
      return (a.start_time ?? '').localeCompare(b.start_time ?? '')
    })
    for (const s of sorted) {
      if (!map.has(s.date)) map.set(s.date, [])
      map.get(s.date)!.push(s)
    }
    return Array.from(map.entries()).map(([date, spots]) => ({ date, label: fmtLong(date), spots }))
  }

  function categoryFor(id: SpotCategory) { return SPOT_CATEGORIES.find(c => c.id === id) ?? SPOT_CATEGORIES[1] }

  function isUpcoming(t: Trip): boolean { return (t.end_date ?? t.start_date) >= todayDate }

  // ── View state ─────────────────────────────────────────────────────────────
  type View = 'list' | 'trip'
  type TripTab = 'route' | 'pack' | 'docs'

  let view: View = 'list'
  let activeTrip: Trip | null = null
  let tripTab: TripTab = 'route'
  let loading = true

  // ── Data ───────────────────────────────────────────────────────────────────
  let trips: Trip[] = []
  let spots: TripSpot[] = []
  let bags: PackingBag[] = []
  let packItems: PackingItem[] = []
  let documents: TripDocument[] = []

  // ── Modal states ───────────────────────────────────────────────────────────
  let showTripModal = false
  let showSpotModal = false
  let showBagModal = false
  let showItemModal = false
  let editingTrip: Trip | null = null
  let editingSpot: TripSpot | null = null
  let editingBag: PackingBag | null = null
  let editingItem: PackingItem | null = null

  // ── Trip form ──────────────────────────────────────────────────────────────
  let fTitle = ''
  let fCity = ''
  let fCountry = ''
  let fStartDate = todayDate
  let fEndDate = ''
  let fNotes = ''
  let fEmoji = '✈️'

  // ── Spot form ──────────────────────────────────────────────────────────────
  let fSpotName = ''
  let fSpotCategory: SpotCategory = 'place'
  let fSpotDate = ''
  let fSpotStartTime = ''
  let fSpotEndTime = ''
  let fSpotAddress = ''
  let fSpotNotes = ''

  // ── Bag form ──────────────────────────────────────────────────────────────
  let fBagName = ''
  let fBagWeightLimit = ''

  // ── Item form ─────────────────────────────────────────────────────────────
  let fItemName = ''
  let fItemBagId = ''

  // ── Filter state ──────────────────────────────────────────────────────────
  let spotFilter: SpotCategory | null = null

  // ── Doc upload ────────────────────────────────────────────────────────────
  let uploading = false

  // ── Derived ───────────────────────────────────────────────────────────────
  $: grouped = groupByMonth(trips)
  $: tripSpots = spots.filter(s => s.trip_id === activeTrip?.id)
  $: filteredSpots = spotFilter ? tripSpots.filter(s => s.category === spotFilter) : tripSpots
  $: groupedSpots = groupByDate(filteredSpots)
  $: tripBags = bags.filter(b => b.trip_id === activeTrip?.id)
  $: tripItems = packItems.filter(i => i.trip_id === activeTrip?.id)
  $: tripDocs = documents.filter(d => d.trip_id === activeTrip?.id)
  $: photoDocs = tripDocs.filter(d => d.file_type === 'photo')
  $: pdfDocs   = tripDocs.filter(d => d.file_type === 'pdf')

  // Reactive bag/item grouping — avoids calling functions inside {#each} that won't re-trigger
  $: looseItems = tripItems.filter(i => i.bag_id === null).sort((a, b) => a.sort_order - b.sort_order)
  $: enrichedBags = tripBags.map(bag => {
    const items = tripItems.filter(i => i.bag_id === bag.id).sort((a, b) => a.sort_order - b.sort_order)
    return { bag, items, packed: items.filter(i => i.packed).length }
  })

  // ── Data loading ──────────────────────────────────────────────────────────
  async function loadTrips() {
    loading = true
    const { data } = await supabase.from('trips')
      .select('*').eq('user_id', $user!.id).order('start_date', { ascending: false })
    trips = data ?? []
    loading = false
  }

  async function loadTripData(tripId: string) {
    const [s, b, i, d] = await Promise.all([
      supabase.from('trip_spots').select('*').eq('trip_id', tripId),
      supabase.from('packing_bags').select('*').eq('trip_id', tripId).order('sort_order'),
      supabase.from('packing_items').select('*').eq('trip_id', tripId).order('sort_order'),
      supabase.from('trip_documents').select('*').eq('trip_id', tripId).order('created_at'),
    ])
    spots = [...spots.filter(x => x.trip_id !== tripId), ...(s.data ?? [])]
    bags = [...bags.filter(x => x.trip_id !== tripId), ...(b.data ?? [])]
    packItems = [...packItems.filter(x => x.trip_id !== tripId), ...(i.data ?? [])]
    documents = [...documents.filter(x => x.trip_id !== tripId), ...(d.data ?? [])]
  }

  async function openTrip(t: Trip) {
    activeTrip = t
    tripTab = 'route'
    spotFilter = null
    view = 'trip'
    await loadTripData(t.id)
  }

  function backToList() {
    view = 'list'
    activeTrip = null
  }

  // ── Trip CRUD ─────────────────────────────────────────────────────────────
  function openNewTrip() {
    editingTrip = null
    fTitle = ''; fCity = ''; fCountry = ''; fStartDate = todayDate; fEndDate = ''; fNotes = ''; fEmoji = '✈️'
    showTripModal = true
  }

  function openEditTrip(t: Trip) {
    editingTrip = t
    fTitle = t.title; fCity = t.city; fCountry = t.country ?? ''
    fStartDate = t.start_date; fEndDate = t.end_date ?? ''; fNotes = t.notes ?? ''; fEmoji = t.cover_emoji
    showTripModal = true
  }

  async function saveTrip() {
    if (!fCity.trim()) return
    const payload = {
      user_id: $user!.id,
      title: fTitle.trim() || fCity.trim(),
      city: fCity.trim(),
      country: fCountry.trim() || null,
      start_date: fStartDate,
      end_date: fEndDate || null,
      notes: fNotes.trim() || null,
      cover_emoji: fEmoji,
    }
    if (editingTrip) {
      const { data } = await supabase.from('trips').update(payload).eq('id', editingTrip.id).select().single()
      if (data) trips = trips.map(t => t.id === data.id ? data : t)
      if (activeTrip?.id === editingTrip.id) activeTrip = data
    } else {
      const { data } = await supabase.from('trips').insert(payload).select().single()
      if (data) trips = [data, ...trips]
    }
    showTripModal = false
  }

  async function deleteTrip(id: string) {
    await supabase.from('trips').delete().eq('id', id)
    trips = trips.filter(t => t.id !== id)
    if (activeTrip?.id === id) backToList()
    showToast('Поездка удалена', 'success')
  }

  // ── Spot CRUD ─────────────────────────────────────────────────────────────
  function openAddSpot() {
    editingSpot = null
    fSpotName = ''; fSpotCategory = 'place'
    fSpotDate = activeTrip?.start_date ?? todayDate
    fSpotStartTime = ''; fSpotEndTime = ''; fSpotAddress = ''; fSpotNotes = ''
    showSpotModal = true
  }

  function openEditSpot(spot: TripSpot) {
    editingSpot = spot
    fSpotName = spot.name; fSpotCategory = spot.category; fSpotDate = spot.date
    fSpotStartTime = spot.start_time ?? ''; fSpotEndTime = spot.end_time ?? ''
    fSpotAddress = spot.address ?? ''; fSpotNotes = spot.notes ?? ''
    showSpotModal = true
  }

  async function saveSpot() {
    if (!fSpotName.trim() || !activeTrip) return
    const payload = {
      name: fSpotName.trim(), category: fSpotCategory, date: fSpotDate,
      start_time: fSpotStartTime || null, end_time: fSpotEndTime || null,
      address: fSpotAddress.trim() || null, notes: fSpotNotes.trim() || null,
    }
    if (editingSpot) {
      const { data } = await supabase.from('trip_spots').update(payload).eq('id', editingSpot.id).select().single()
      if (data) spots = spots.map(s => s.id === data.id ? data : s)
    } else {
      const { data } = await supabase.from('trip_spots').insert({
        ...payload, user_id: $user!.id, trip_id: activeTrip.id, sort_order: tripSpots.length,
      }).select().single()
      if (data) spots = [...spots, data]
    }
    showSpotModal = false
  }

  async function deleteSpot(id: string) {
    await supabase.from('trip_spots').delete().eq('id', id)
    spots = spots.filter(s => s.id !== id)
    showSpotModal = false
  }

  // ── Bag CRUD ──────────────────────────────────────────────────────────────
  function openAddBag() {
    editingBag = null; fBagName = ''; fBagWeightLimit = ''; showBagModal = true
  }

  function openEditBag(bag: PackingBag) {
    editingBag = bag; fBagName = bag.name
    fBagWeightLimit = bag.weight_limit_kg != null ? String(bag.weight_limit_kg) : ''
    showBagModal = true
  }

  async function saveBag() {
    if (!fBagName.trim() || !activeTrip) return
    const wl = fBagWeightLimit ? parseFloat(fBagWeightLimit) : null
    if (editingBag) {
      const { data } = await supabase.from('packing_bags')
        .update({ name: fBagName.trim(), weight_limit_kg: wl })
        .eq('id', editingBag.id).select().single()
      if (data) bags = bags.map(b => b.id === data.id ? data : b)
    } else {
      const { data } = await supabase.from('packing_bags').insert({
        user_id: $user!.id, trip_id: activeTrip.id, name: fBagName.trim(),
        weight_limit_kg: wl, sort_order: tripBags.length,
      }).select().single()
      if (data) bags = [...bags, data]
    }
    showBagModal = false
  }

  async function deleteBag(id: string) {
    await supabase.from('packing_bags').delete().eq('id', id)
    bags = bags.filter(b => b.id !== id)
    packItems = packItems.map(i => i.bag_id === id ? { ...i, bag_id: null } : i)
    showBagModal = false
  }

  // ── Item CRUD ─────────────────────────────────────────────────────────────
  function openAddItem(defaultBagId?: string) {
    editingItem = null; fItemName = ''; fItemBagId = defaultBagId ?? ''
    showItemModal = true
  }

  function openEditItem(item: PackingItem) {
    editingItem = item; fItemName = item.name; fItemBagId = item.bag_id ?? ''
    showItemModal = true
  }

  async function saveItem() {
    if (!fItemName.trim() || !activeTrip) return
    if (editingItem) {
      const { data } = await supabase.from('packing_items')
        .update({ name: fItemName.trim(), bag_id: fItemBagId || null })
        .eq('id', editingItem.id).select().single()
      if (data) packItems = packItems.map(i => i.id === data.id ? data : i)
    } else {
      const { data } = await supabase.from('packing_items').insert({
        user_id: $user!.id, trip_id: activeTrip.id,
        bag_id: fItemBagId || null, name: fItemName.trim(),
        packed: false, sort_order: tripItems.length,
      }).select().single()
      if (data) packItems = [...packItems, data]
    }
    showItemModal = false
  }

  async function toggleItem(item: PackingItem) {
    const packed = !item.packed
    packItems = packItems.map(i => i.id === item.id ? { ...i, packed } : i)
    await supabase.from('packing_items').update({ packed }).eq('id', item.id)
  }

  async function deleteItem(id: string) {
    await supabase.from('packing_items').delete().eq('id', id)
    packItems = packItems.filter(i => i.id !== id)
    showItemModal = false
  }

  // ── Documents ─────────────────────────────────────────────────────────────
  let fileInput: HTMLInputElement

  async function handleFileSelect(e: Event) {
    const file = (e.target as HTMLInputElement).files?.[0]
    if (!file || !activeTrip) return
    uploading = true
    const ext = file.name.split('.').pop() ?? ''
    const path = `${$user!.id}/${activeTrip.id}/${Date.now()}.${ext}`
    const url = await uploadFile('trip-docs', path, file)
    if (url) {
      const fileType: 'photo' | 'pdf' = file.type.startsWith('image/') ? 'photo' : 'pdf'
      const { data } = await supabase.from('trip_documents').insert({
        user_id: $user!.id, trip_id: activeTrip.id, name: file.name, file_url: url, file_type: fileType,
      }).select().single()
      if (data) documents = [...documents, data]
      showToast('Файл загружен', 'success')
    } else {
      showToast('Ошибка загрузки', 'error')
    }
    uploading = false
    if (fileInput) fileInput.value = ''
  }

  async function deleteDoc(id: string) {
    await supabase.from('trip_documents').delete().eq('id', id)
    documents = documents.filter(d => d.id !== id)
  }

  let lightboxUrl: string | null = null

  onMount(loadTrips)
</script>

<!-- ══════════════════════════════════════════════════════════ LIST VIEW ══ -->
{#if view === 'list'}
  <div class="page-shell">
    <header class="page-header">
      <div class="header-text">
        <h1 class="page-title">Путешествия</h1>
      </div>
    </header>

    {#if loading}
      <p class="muted-hint">Загрузка...</p>
    {:else if trips.length === 0}
      <div class="empty-state">
        <div class="empty-icon">{@html icons.plane}</div>
        <p class="empty-title">Нет поездок</p>
        <p class="empty-sub">Добавь свою первую поездку</p>
      </div>
    {:else}
      {#each grouped as group}
        <div class="month-group">
          <p class="month-label">{group.label}</p>
          <div class="trip-list">
            {#each group.trips as trip}
              <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
              <div class="trip-card" on:click={() => openTrip(trip)}>
                <div class="trip-emoji">{trip.cover_emoji}</div>
                <div class="trip-info">
                  <span class="trip-city">{trip.city}{trip.country ? `, ${trip.country}` : ''}</span>
                  <span class="trip-dates">{tripDateRange(trip)}</span>
                  {#if trip.title !== trip.city}
                    <span class="trip-title-hint">{trip.title}</span>
                  {/if}
                </div>
                <div class="trip-arrow">{@html icons.edit}</div>
              </div>
            {/each}
          </div>
        </div>
      {/each}
    {/if}
  </div>

  <!-- FAB -->
  <button class="fab" on:click={openNewTrip} aria-label="Добавить поездку">
    {@html icons.plus}
  </button>

<!-- ══════════════════════════════════════════════════════════ TRIP VIEW ══ -->
{:else if view === 'trip' && activeTrip}
  <div class="page-shell">
    <header class="page-header">
      <button class="back-btn" on:click={backToList} aria-label="Назад">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M15 18l-6-6 6-6"/>
        </svg>
      </button>
      <div class="header-text">
        <h1 class="page-title" style="font-size:1.25rem">{activeTrip.cover_emoji} {activeTrip.city}</h1>
        <p class="trip-header-dates">{tripDateRange(activeTrip)}</p>
      </div>
      <button class="icon-btn" on:click={() => activeTrip && openEditTrip(activeTrip)} aria-label="Редактировать">
        {@html icons.edit}
      </button>
    </header>

    <!-- Tab bar -->
    <div class="tab-bar">
      <button class="tab-btn" class:active={tripTab === 'route'} on:click={() => tripTab = 'route'}>Маршрут</button>
      <button class="tab-btn" class:active={tripTab === 'pack'}  on:click={() => tripTab = 'pack'}>Чемодан</button>
      <button class="tab-btn" class:active={tripTab === 'docs'}  on:click={() => tripTab = 'docs'}>Документы</button>
    </div>

    <!-- ── ROUTE tab ── -->
    {#if tripTab === 'route'}
      <div class="cat-filter-row">
        <button class="filter-chip" class:active={spotFilter === null} on:click={() => spotFilter = null}>Все</button>
        {#each SPOT_CATEGORIES as cat}
          <button class="filter-chip" class:active={spotFilter === cat.id} on:click={() => spotFilter = cat.id}>{cat.label}</button>
        {/each}
      </div>

      {#if groupedSpots.length === 0}
        <div class="empty-state small">
          <p class="empty-sub">Нет мест в маршруте</p>
        </div>
      {:else}
        {#each groupedSpots as dayGroup}
          <p class="day-label">{dayGroup.label}</p>
          <div class="spot-list">
            {#each dayGroup.spots as spot}
              <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
              <div class="spot-card" on:click={() => openEditSpot(spot)}>
                <div class="spot-icon">{@html categoryFor(spot.category).icon}</div>
                <div class="spot-info">
                  <span class="spot-name">{spot.name}</span>
                  {#if spot.start_time}
                    <span class="spot-time">{spot.start_time.slice(0,5)}{spot.end_time ? ' – ' + spot.end_time.slice(0,5) : ''}</span>
                  {/if}
                  {#if spot.address}
                    <span class="spot-address">{spot.address}</span>
                  {/if}
                </div>
              </div>
            {/each}
          </div>
        {/each}
      {/if}

    <!-- ── PACK tab ── -->
    {:else if tripTab === 'pack'}
      {#if enrichedBags.length === 0 && looseItems.length === 0}
        <div class="empty-state small">
          <p class="empty-sub">Чемодан пуст — добавь вещи</p>
        </div>
      {/if}

      {#if looseItems.length > 0 || enrichedBags.length === 0}
        <div class="bag-section">
          <div class="bag-header">
            <span class="bag-name">Общее</span>
            <span class="bag-count">{looseItems.filter(i => i.packed).length}/{looseItems.length}</span>
          </div>
          <div class="item-list">
            {#each looseItems as item}
              <div class="item-row">
                <button class="checkbox" class:checked={item.packed} on:click={() => toggleItem(item)}>
                  {#if item.packed}<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>{/if}
                </button>
                <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
                <span class="item-name" class:packed={item.packed} on:click={() => openEditItem(item)}>{item.name}</span>
              </div>
            {/each}
          </div>
          <button class="add-item-btn" on:click={() => openAddItem(undefined)}>+ Добавить</button>
        </div>
      {/if}

      {#each enrichedBags as { bag, items, packed }}
        <div class="bag-section">
          <div class="bag-header">
            <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
            <span class="bag-name clickable" on:click={() => openEditBag(bag)}>{bag.name}</span>
            <span class="bag-count">{packed}/{items.length}{bag.weight_limit_kg ? ` · лимит ${bag.weight_limit_kg} кг` : ''}</span>
          </div>
          <div class="progress-bar">
            <div class="progress-fill" style="width:{items.length ? (packed/items.length)*100 : 0}%"></div>
          </div>
          <div class="item-list">
            {#each items as item}
              <div class="item-row">
                <button class="checkbox" class:checked={item.packed} on:click={() => toggleItem(item)}>
                  {#if item.packed}<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>{/if}
                </button>
                <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
                <span class="item-name" class:packed={item.packed} on:click={() => openEditItem(item)}>{item.name}</span>
              </div>
            {/each}
          </div>
          <button class="add-item-btn" on:click={() => openAddItem(bag.id)}>+ Добавить</button>
        </div>
      {/each}

      <button class="add-bag-btn" on:click={openAddBag}>+ Добавить сумку / багаж</button>

    <!-- ── DOCS tab ── -->
    {:else if tripTab === 'docs'}
      {#if photoDocs.length === 0 && pdfDocs.length === 0}
        <div class="empty-state small">
          <p class="empty-sub">Нет документов — загрузи фото или PDF</p>
        </div>
      {/if}

      {#if photoDocs.length > 0}
        <p class="section-sub-label">Фотографии</p>
        <div class="photo-grid">
          {#each photoDocs as doc}
            <div class="photo-cell">
              <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
              <img src={doc.file_url} alt={doc.name} on:click={() => lightboxUrl = doc.file_url} />
              <button class="photo-delete" on:click={() => deleteDoc(doc.id)} aria-label="Удалить">×</button>
            </div>
          {/each}
        </div>
      {/if}

      {#if pdfDocs.length > 0}
        <p class="section-sub-label">Документы</p>
        <div class="pdf-list">
          {#each pdfDocs as doc}
            <div class="pdf-card">
              <div class="pdf-icon">{@html icons.file_text}</div>
              <a class="pdf-name" href={doc.file_url} target="_blank" rel="noopener">{doc.name}</a>
              <button class="delete-btn-sm" on:click={() => deleteDoc(doc.id)} aria-label="Удалить">×</button>
            </div>
          {/each}
        </div>
      {/if}
    {/if}
  </div>

  <!-- FAB per tab -->
  {#if tripTab === 'route'}
    <button class="fab" on:click={openAddSpot} aria-label="Добавить место">
      {@html icons.plus}
    </button>
  {:else if tripTab === 'docs'}
    <button class="fab" class:uploading on:click={() => fileInput?.click()} aria-label="Загрузить файл">
      {#if uploading}
        <span class="spin">↻</span>
      {:else}
        {@html icons.plus}
      {/if}
    </button>
    <input bind:this={fileInput} type="file" accept="image/*,.pdf" class="hidden-input" on:change={handleFileSelect} />
  {/if}
{/if}

<!-- ══════════════════ MODALS ══════════════════════════════════════════════ -->

<!-- Trip modal -->
<Modal title={editingTrip ? 'Редактировать поездку' : 'Новая поездка'} open={showTripModal} on:close={() => showTripModal = false}>
  <div class="form-group">
    <label class="form-label">Город *</label>
    <input class="form-input" bind:value={fCity} placeholder="Москва, Стамбул…" />
  </div>
  <div class="form-group">
    <label class="form-label">Страна</label>
    <input class="form-input" bind:value={fCountry} placeholder="Россия, Турция…" />
  </div>
  <div class="form-group">
    <label class="form-label">Название поездки</label>
    <input class="form-input" bind:value={fTitle} placeholder="Оставь пустым = город" />
  </div>
  <div class="form-row">
    <div class="form-group" style="flex:1">
      <label class="form-label">Начало *</label>
      <input class="form-input" type="date" bind:value={fStartDate} />
    </div>
    <div class="form-group" style="flex:1">
      <label class="form-label">Конец</label>
      <input class="form-input" type="date" bind:value={fEndDate} />
    </div>
  </div>
  <div class="form-group">
    <label class="form-label">Значок</label>
    <div class="emoji-row">
      {#each TRIP_EMOJIS as e}
        <button class="emoji-btn" class:active={fEmoji === e} on:click={() => fEmoji = e}>{e}</button>
      {/each}
    </div>
  </div>
  <div class="form-group">
    <label class="form-label">Заметки</label>
    <textarea class="form-input" rows="2" bind:value={fNotes} placeholder="…"></textarea>
  </div>
  <div class="form-actions">
    {#if editingTrip}
      {@const tripToDelete = editingTrip}
      <button class="btn-danger" on:click={() => { deleteTrip(tripToDelete.id); showTripModal = false }}>Удалить</button>
    {/if}
    <button class="btn-primary" on:click={saveTrip}>Сохранить</button>
  </div>
</Modal>

<!-- Spot modal -->
<Modal title={editingSpot ? 'Редактировать место' : 'Добавить место'} open={showSpotModal} on:close={() => showSpotModal = false}>
  <div class="form-group">
    <label class="form-label">Название *</label>
    <input class="form-input" bind:value={fSpotName} placeholder="Голубая мечеть…" />
  </div>
  <div class="form-group">
    <label class="form-label">Категория</label>
    <div class="cat-row">
      {#each SPOT_CATEGORIES as cat}
        <button class="cat-chip" class:active={fSpotCategory === cat.id} on:click={() => fSpotCategory = cat.id}>{cat.label}</button>
      {/each}
    </div>
  </div>
  <div class="form-group">
    <label class="form-label">Дата</label>
    <input class="form-input" type="date" bind:value={fSpotDate} />
  </div>
  <div class="form-row">
    <div class="form-group" style="flex:1">
      <label class="form-label">Начало</label>
      <input class="form-input" type="time" bind:value={fSpotStartTime} />
    </div>
    <div class="form-group" style="flex:1">
      <label class="form-label">Конец</label>
      <input class="form-input" type="time" bind:value={fSpotEndTime} />
    </div>
  </div>
  <div class="form-group">
    <label class="form-label">Адрес</label>
    <input class="form-input" bind:value={fSpotAddress} placeholder="Ул. Примерная, 1" />
  </div>
  <div class="form-group">
    <label class="form-label">Заметки</label>
    <textarea class="form-input" rows="2" bind:value={fSpotNotes} placeholder="…"></textarea>
  </div>
  <div class="form-actions">
    {#if editingSpot}
      {@const spotToDelete = editingSpot}
      <button class="btn-danger" on:click={() => deleteSpot(spotToDelete.id)}>Удалить</button>
    {/if}
    <button class="btn-primary" on:click={saveSpot}>{editingSpot ? 'Сохранить' : 'Добавить'}</button>
  </div>
</Modal>

<!-- Bag modal -->
<Modal title={editingBag ? 'Редактировать багаж' : 'Новая сумка'} open={showBagModal} on:close={() => showBagModal = false}>
  <div class="form-group">
    <label class="form-label">Название</label>
    <input class="form-input" bind:value={fBagName} placeholder="Чемодан, Рюкзак, Ручная кладь…" />
  </div>
  <div class="form-group">
    <label class="form-label">Лимит веса (кг)</label>
    <input class="form-input" type="number" step="0.1" bind:value={fBagWeightLimit} placeholder="Напр. 10" />
  </div>
  <div class="form-actions">
    {#if editingBag}
      {@const bagToDelete = editingBag}
      <button class="btn-danger" on:click={() => deleteBag(bagToDelete.id)}>Удалить</button>
    {/if}
    <button class="btn-primary" on:click={saveBag}>Сохранить</button>
  </div>
</Modal>

<!-- Item modal -->
<Modal title={editingItem ? 'Редактировать вещь' : 'Добавить вещь'} open={showItemModal} on:close={() => showItemModal = false}>
  <div class="form-group">
    <label class="form-label">Название *</label>
    <input class="form-input" bind:value={fItemName} placeholder="Паспорт, Зарядка…" />
  </div>
  {#if tripBags.length > 0}
    <div class="form-group">
      <label class="form-label">Сумка</label>
      <select class="form-input" bind:value={fItemBagId}>
        <option value="">Общее</option>
        {#each tripBags as bag}
          <option value={bag.id}>{bag.name}</option>
        {/each}
      </select>
    </div>
  {/if}
  <div class="form-actions">
    {#if editingItem}
      {@const itemToDelete = editingItem}
      <button class="btn-danger" on:click={() => deleteItem(itemToDelete.id)}>Удалить</button>
    {/if}
    <button class="btn-primary" on:click={saveItem}>{editingItem ? 'Сохранить' : 'Добавить'}</button>
  </div>
</Modal>

<!-- Lightbox -->
{#if lightboxUrl}
  <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
  <div class="lightbox" on:click={() => lightboxUrl = null}>
    <img src={lightboxUrl} alt="preview" />
  </div>
{/if}

<style>
  .page-shell {
    max-width: 480px;
    margin: 0 auto;
    padding: 0 1.375rem 8rem;
    min-height: 100dvh;
  }

  .page-header {
    display: flex;
    align-items: flex-start;
    gap: 0.5rem;
    padding: 1rem 0 0.75rem;
  }

  .header-text { flex: 1; }

  .page-title {
    font-family: "Fraunces", serif;
    font-size: 1.75rem;
    font-weight: 300;
    color: var(--color-text);
    margin: 0;
    letter-spacing: -0.02em;
  }

  .trip-header-dates {
    font-size: 0.8125rem;
    color: var(--color-muted);
    margin: 0.125rem 0 0;
  }

  .back-btn {
    background: none; border: none; color: var(--color-accent);
    cursor: pointer; padding: 0.25rem; margin-top: 0.125rem;
    -webkit-tap-highlight-color: transparent;
  }

  .icon-btn {
    background: none; border: none; cursor: pointer;
    color: var(--color-muted); padding: 0.25rem;
    width: 1.75rem; height: 1.75rem;
    -webkit-tap-highlight-color: transparent;
  }
  .icon-btn :global(svg) { width: 100%; height: 100%; }

  /* ── Trip list ── */
  .month-group { margin-bottom: 1.5rem; }

  .month-label {
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted);
    margin: 0 0 0.5rem;
  }

  .trip-list { display: flex; flex-direction: column; gap: 0.5rem; }

  .trip-card {
    display: flex;
    align-items: center;
    gap: 0.875rem;
    padding: 0.875rem 1rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
  }
  .trip-card:active { transform: scale(0.98); opacity: 0.85; }

  .trip-emoji { font-size: 1.75rem; line-height: 1; flex-shrink: 0; }

  .trip-info {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .trip-city { font-size: 1rem; font-weight: 500; color: var(--color-text); font-family: "Fraunces", serif; }
  .trip-dates { font-size: 0.8125rem; color: var(--color-muted); }
  .trip-title-hint { font-size: 0.75rem; color: var(--color-muted); font-style: italic; }

  .trip-arrow { width: 1rem; height: 1rem; color: var(--color-muted); flex-shrink: 0; }
  .trip-arrow :global(svg) { width: 100%; height: 100%; }

  /* ── Tab bar ── */
  .tab-bar {
    display: flex;
    gap: 0.25rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    padding: 0.25rem;
    margin-bottom: 1rem;
  }

  .tab-btn {
    flex: 1;
    padding: 0.5rem;
    background: none;
    border: none;
    border-radius: 0.625rem;
    font-size: 0.875rem;
    color: var(--color-muted);
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
    font-family: "Source Serif 4", serif;
  }
  .tab-btn.active {
    background: var(--color-bg);
    color: var(--color-text);
    font-weight: 500;
  }

  /* ── Spot filter ── */
  .cat-filter-row {
    display: flex;
    gap: 0.375rem;
    flex-wrap: nowrap;
    overflow-x: auto;
    padding-bottom: 0.25rem;
    margin-bottom: 0.75rem;
    scrollbar-width: none;
  }
  .cat-filter-row::-webkit-scrollbar { display: none; }

  .filter-chip {
    flex-shrink: 0;
    padding: 0.3125rem 0.75rem;
    border-radius: 999px;
    border: 1px solid var(--color-border);
    background: var(--color-card);
    font-size: 0.8125rem;
    color: var(--color-muted);
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    white-space: nowrap;
  }
  .filter-chip.active {
    background: var(--color-accent);
    border-color: var(--color-accent);
    color: white;
  }

  /* ── Day groups ── */
  .day-label {
    font-size: 0.75rem;
    color: var(--color-muted);
    margin: 0.75rem 0 0.375rem;
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .spot-list { display: flex; flex-direction: column; gap: 0.5rem; margin-bottom: 0.25rem; }

  .spot-card {
    display: flex;
    align-items: flex-start;
    gap: 0.75rem;
    padding: 0.75rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: opacity 0.15s;
  }
  .spot-card:active { opacity: 0.7; }

  .spot-icon {
    width: 1.75rem;
    height: 1.75rem;
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 0.5rem;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--color-accent);
    flex-shrink: 0;
    padding: 0.3rem;
  }
  .spot-icon :global(svg) { width: 100%; height: 100%; }

  .spot-info { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .spot-name { font-size: 0.9375rem; color: var(--color-text); font-weight: 500; }
  .spot-time { font-size: 0.75rem; color: var(--color-accent); }
  .spot-address { font-size: 0.75rem; color: var(--color-muted); }

  /* ── Packing ── */
  .bag-section {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1rem;
    padding: 0.875rem;
    margin-bottom: 0.75rem;
  }

  .bag-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 0.5rem;
  }

  .bag-name { font-size: 0.9375rem; font-weight: 500; color: var(--color-text); flex: 1; }
  .bag-name.clickable { cursor: pointer; text-decoration: underline dotted var(--color-muted); }
  .bag-count { font-size: 0.75rem; color: var(--color-muted); }

  .progress-bar {
    height: 3px;
    background: var(--color-border);
    border-radius: 2px;
    overflow: hidden;
    margin-bottom: 0.75rem;
  }
  .progress-fill {
    height: 100%;
    background: var(--color-accent);
    border-radius: 2px;
    transition: width 0.3s;
  }

  .item-list { display: flex; flex-direction: column; gap: 0.375rem; }

  .item-row {
    display: flex;
    align-items: center;
    gap: 0.625rem;
  }

  .checkbox {
    width: 1.25rem;
    height: 1.25rem;
    border-radius: 0.375rem;
    border: 1.5px solid var(--color-border);
    background: var(--color-bg);
    cursor: pointer;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
    padding: 0;
  }
  .checkbox.checked { background: var(--color-accent); border-color: var(--color-accent); }
  .checkbox :global(svg) { width: 0.75rem; height: 0.75rem; stroke: white; }

  .item-name { flex: 1; font-size: 0.9rem; color: var(--color-text); cursor: pointer; }
  .item-name.packed { text-decoration: line-through; color: var(--color-muted); }

  .add-item-btn {
    margin-top: 0.625rem;
    background: none; border: none; cursor: pointer;
    font-size: 0.8125rem; color: var(--color-accent);
    padding: 0; -webkit-tap-highlight-color: transparent;
  }

  .add-bag-btn {
    width: 100%;
    padding: 0.75rem;
    background: none;
    border: 1.5px dashed var(--color-border);
    border-radius: 1rem;
    font-size: 0.875rem;
    color: var(--color-muted);
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
  }
  .add-bag-btn:active { opacity: 0.6; }

  /* ── Documents ── */
  .section-sub-label {
    font-size: 0.75rem;
    color: var(--color-muted);
    text-transform: uppercase;
    letter-spacing: 0.06em;
    margin: 0.75rem 0 0.5rem;
  }

  .photo-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 0.375rem;
    margin-bottom: 1rem;
  }

  .photo-cell {
    position: relative;
    aspect-ratio: 1;
    border-radius: 0.625rem;
    overflow: hidden;
    background: var(--color-card);
    border: 1px solid var(--color-border);
  }

  .photo-cell img {
    width: 100%; height: 100%; object-fit: cover; cursor: pointer;
  }

  .photo-delete {
    position: absolute;
    top: 0.25rem; right: 0.25rem;
    width: 1.25rem; height: 1.25rem;
    background: rgba(0,0,0,0.5);
    color: white;
    border: none; border-radius: 50%;
    font-size: 0.875rem; line-height: 1;
    cursor: pointer; display: flex; align-items: center; justify-content: center;
    -webkit-tap-highlight-color: transparent;
  }

  .pdf-list { display: flex; flex-direction: column; gap: 0.5rem; }

  .pdf-card {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.75rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
  }

  .pdf-icon {
    width: 1.75rem; height: 1.75rem;
    color: var(--color-accent); flex-shrink: 0;
  }
  .pdf-icon :global(svg) { width: 100%; height: 100%; }

  .pdf-name {
    flex: 1; font-size: 0.875rem; color: var(--color-text);
    text-decoration: none; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }

  /* ── Empty states ── */
  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.75rem;
    padding: 3rem 1rem;
  }
  .empty-state.small { padding: 1.5rem 1rem; }

  .empty-icon {
    width: 3rem; height: 3rem; color: var(--color-muted);
  }
  .empty-icon :global(svg) { width: 100%; height: 100%; }

  .empty-title {
    font-family: "Fraunces", serif;
    font-size: 1.25rem;
    font-weight: 300;
    color: var(--color-text);
    margin: 0;
  }
  .empty-sub { font-size: 0.875rem; color: var(--color-muted); margin: 0; text-align: center; }

  .muted-hint { color: var(--color-muted); font-size: 0.875rem; text-align: center; margin-top: 2rem; }

  /* ── FAB ── */
  .fab {
    position: fixed;
    bottom: calc(4.5rem + env(safe-area-inset-bottom));
    right: max(1.25rem, calc(50vw - 240px + 1.25rem));
    width: 3.25rem;
    height: 3.25rem;
    border-radius: 50%;
    background: var(--color-accent);
    color: white;
    border: none;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 4px 16px rgba(0,0,0,0.18);
    -webkit-tap-highlight-color: transparent;
    transition: transform 0.15s;
    z-index: 50;
    padding: 0.875rem;
  }
  .fab :global(svg) { width: 100%; height: 100%; }
  .fab:active { transform: scale(0.93); }
  .fab.uploading { opacity: 0.6; }

  .spin { font-size: 1.25rem; animation: spin 0.8s linear infinite; display: inline-block; }
  @keyframes spin { to { transform: rotate(360deg); } }

  .hidden-input { display: none; }

  /* ── Forms ── */
  .form-group { margin-bottom: 0.875rem; }
  .form-label { display: block; font-size: 0.8125rem; color: var(--color-muted); margin-bottom: 0.375rem; }
  .form-input {
    width: 100%; padding: 0.625rem 0.75rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    font-size: 0.9375rem; color: var(--color-text);
    font-family: inherit; box-sizing: border-box;
    -webkit-appearance: none;
  }
  .form-input:focus { outline: none; border-color: var(--color-accent); }

  .form-row { display: flex; gap: 0.75rem; }

  .form-actions {
    display: flex;
    gap: 0.625rem;
    justify-content: flex-end;
    margin-top: 0.5rem;
  }

  .btn-primary {
    padding: 0.625rem 1.25rem;
    background: var(--color-accent);
    color: white; border: none;
    border-radius: 0.75rem;
    font-size: 0.9375rem; cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    font-family: inherit;
  }
  .btn-primary:active { opacity: 0.8; }

  .btn-danger {
    padding: 0.625rem 1rem;
    background: none;
    color: #e53935; border: 1px solid #e53935;
    border-radius: 0.75rem;
    font-size: 0.9375rem; cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    font-family: inherit;
  }
  .btn-danger:active { opacity: 0.7; }

  .emoji-row { display: flex; gap: 0.5rem; flex-wrap: wrap; }

  .emoji-btn {
    font-size: 1.5rem;
    width: 2.5rem; height: 2.5rem;
    border: 1.5px solid var(--color-border);
    border-radius: 0.625rem;
    background: var(--color-card);
    cursor: pointer;
    display: flex; align-items: center; justify-content: center;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
  }
  .emoji-btn.active { border-color: var(--color-accent); background: var(--color-bg); }

  .cat-row { display: flex; gap: 0.375rem; flex-wrap: wrap; }

  .cat-chip {
    padding: 0.3125rem 0.75rem;
    border-radius: 999px;
    border: 1px solid var(--color-border);
    background: var(--color-card);
    font-size: 0.8125rem;
    color: var(--color-muted);
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
  }
  .cat-chip.active {
    background: var(--color-accent);
    border-color: var(--color-accent);
    color: white;
  }

  .delete-btn-sm {
    background: none; border: none; cursor: pointer;
    color: var(--color-muted); font-size: 1.125rem; line-height: 1;
    width: 1.5rem; height: 1.5rem;
    display: flex; align-items: center; justify-content: center;
    flex-shrink: 0; -webkit-tap-highlight-color: transparent;
  }
  .delete-btn-sm:active { opacity: 0.5; }

  /* ── Lightbox ── */
  .lightbox {
    position: fixed; inset: 0; z-index: 300;
    background: rgba(0,0,0,0.85);
    display: flex; align-items: center; justify-content: center;
    cursor: pointer;
  }
  .lightbox img { max-width: 100%; max-height: 100dvh; object-fit: contain; }
</style>
