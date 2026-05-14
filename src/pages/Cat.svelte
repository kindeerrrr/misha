<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../lib/supabase'
  import { user } from '../stores/user'
  import { icons } from '../lib/icons'
  import Modal from '../components/ui/Modal.svelte'
  import { showToast } from '../stores/toast'
  import type { CatProfile, CatVaccine, CatHealthEvent, CatGrooming, CatFoodOrder } from '../lib/types'

  type View = 'list' | 'pet'
  type CatSection = 'vaccines' | 'health' | 'grooming' | 'food'

  const todayDate = today()

  const GROOM_TYPES = ['Грумер', 'Стрижка когтей', 'Чистка ушей', 'Купание']
  const HEALTH_CATEGORIES = [
    { id: 'vet',      label: 'Врач',         icon: icons.stethoscope },
    { id: 'symptom',  label: 'Симптомы',     icon: icons.thermometer },
    { id: 'analysis', label: 'Анализы',      icon: icons.flask },
    { id: 'exam',     label: 'Обследование', icon: icons.scan },
  ]
  const CAT_BREEDS = [
    'Британская короткошёрстная', 'Шотландская вислоухая', 'Шотландская прямоухая', 'Мейн-кун', 'Сибирская',
    'Бенгальская', 'Регдолл', 'Персидская', 'Русская голубая', 'Сфинкс',
    'Норвежская лесная', 'Абиссинская', 'Бурманская', 'Ориентальная',
    'Экзотическая короткошёрстная', 'Турецкая ангора', 'Корниш-рекс', 'Девон-рекс',
    'Манчкин', 'Тайская', 'Другая',
  ]
  const DOG_BREEDS = [
    'Лабрадор', 'Немецкая овчарка', 'Золотистый ретривер', 'Французский бульдог',
    'Хаски', 'Корги', 'Шпиц', 'Йоркширский терьер', 'Мопс', 'Чихуахуа',
    'Бигль', 'Такса', 'Пудель', 'Бордер-колли', 'Самоед',
    'Джек-рассел-терьер', 'Доберман', 'Ротвейлер', 'Боксёр', 'Другая',
  ]
  const CAT_COLORS = [
    'Чёрный', 'Белый', 'Серый', 'Рыжий', 'Кремовый', 'Голубой',
    'Трёхцветный', 'Черепаховый', 'Табби', 'Биколор', 'Колор-пойнт',
    'Золотистая шиншилла', 'Серебристая шиншилла', 'Затушёванный', 'Дымчатый',
  ]
  const DOG_COLORS = [
    'Чёрный', 'Белый', 'Рыжий', 'Коричневый', 'Палевый',
    'Серый', 'Чёрно-белый', 'Рыже-белый', 'Чёрно-подпалый', 'Пятнистый',
  ]
  const ANIMAL_TYPES = [
    { id: 'cat',     label: 'Кошка'  },
    { id: 'dog',     label: 'Собака' },
    { id: 'hamster', label: 'Хомяк'  },
    { id: 'bird',    label: 'Птица'  },
    { id: 'other',   label: 'Другое' },
  ]

  function breedsFor(type: string) { return type === 'dog' ? DOG_BREEDS : type === 'cat' ? CAT_BREEDS : [] }
  function colorsFor(type: string) { return type === 'dog' ? DOG_COLORS : type === 'cat' ? CAT_COLORS : [] }
  function petAge(birthDate: string | null): string | null {
    if (!birthDate) return null
    const birth = new Date(birthDate + 'T12:00:00')
    const now = new Date()
    const totalMonths = (now.getFullYear() - birth.getFullYear()) * 12 + (now.getMonth() - birth.getMonth())
    if (totalMonths < 1) return 'малыш'
    if (totalMonths < 12) return `${totalMonths} мес.`
    const y = Math.floor(totalMonths / 12)
    return `${y} ${y === 1 ? 'год' : y < 5 ? 'года' : 'лет'}`
  }
  function categoryFor(id: string | null) { return HEALTH_CATEGORIES.find(c => c.id === id) ?? HEALTH_CATEGORIES[0] }

  // View state
  let view: View = 'list'
  let catSection: CatSection | null = null
  let loading = true
  let loadError = ''
  let showPetPicker = false

  // Profile
  let profiles: CatProfile[] = []
  let selectedProfile: CatProfile | null = null
  let isNewPet = false
  let showProfileEdit = false

  // Per-pet data
  let vaccines: CatVaccine[] = []
  let healthEvents: CatHealthEvent[] = []
  let groomings: CatGrooming[] = []
  let foodOrders: CatFoodOrder[] = []

  // Filters
  let healthFilter: string | null = null
  let groomingFilter: string | null = null
  let foodBrandFilter: string | null = null

  function sortNearest<T extends { date: string }>(items: T[], nextKey?: string): T[] {
    return [...items].sort((a, b) => {
      const an: string | null = nextKey ? (a as any)[nextKey] : null
      const bn: string | null = nextKey ? (b as any)[nextKey] : null
      const aUp = an && an >= todayDate
      const bUp = bn && bn >= todayDate
      if (aUp && bUp) return an!.localeCompare(bn!)
      if (aUp) return -1
      if (bUp) return 1
      return b.date.localeCompare(a.date)
    })
  }

  $: filteredHealth    = healthFilter    ? healthEvents.filter(e => e.category === healthFilter)   : healthEvents
  $: filteredGroomings = groomingFilter  ? groomings.filter(g => g.type === groomingFilter)        : groomings
  $: foodBrands        = [...new Set(foodOrders.map(f => f.brand))]
  $: filteredFood      = foodBrandFilter ? foodOrders.filter(f => f.brand === foodBrandFilter)     : foodOrders

  $: sortedVaccines  = sortNearest(vaccines,          'next_due')
  $: sortedGroomings = sortNearest(filteredGroomings,  'next_due')
  $: sortedFood      = sortNearest(filteredFood,       'next_order')
  $: sortedHealth    = sortNearest(filteredHealth)

  // Archive helpers
  let showArchived = false
  function daysAgo(d: string | null | undefined): number {
    if (!d) return -9999
    return Math.round((new Date(todayDate + 'T12:00:00').getTime() - new Date(d + 'T12:00:00').getTime()) / 86400000)
  }
  function recState(record: any, nextKey?: string): 'future' | 'recent' | 'past' {
    const trigger: string | null = (nextKey && record[nextKey]) ? record[nextKey] : record.date
    const age = daysAgo(trigger)
    if (age < 0) return 'future'
    if (age <= 7) return 'recent'
    return 'past'
  }

  // Upcoming (sorted by nearest date)
  $: nextVaccine = vaccines.filter(v => v.next_due && v.next_due > todayDate).sort((a,b) => a.next_due!.localeCompare(b.next_due!))[0] ?? null
  $: nextGroom = groomings.filter(g => g.next_due && g.next_due > todayDate).sort((a,b) => a.next_due!.localeCompare(b.next_due!))[0] ?? null
  $: nextFood = foodOrders.filter(f => f.next_order && f.next_order > todayDate).sort((a,b) => a.next_order!.localeCompare(b.next_order!))[0] ?? null
  $: upcomingItems = ([
    nextVaccine ? { label: 'Прививки', name: nextVaccine.name,  date: nextVaccine.next_due ?? '',  icon: icons.pill     } : null,
    nextGroom   ? { label: 'Уход',     name: nextGroom.type,    date: nextGroom.next_due ?? '',    icon: icons.scissors } : null,
    nextFood    ? { label: 'Корм',     name: nextFood.brand,    date: nextFood.next_order ?? '',   icon: icons.bowl     } : null,
  ] as ({ label: string; name: string; date: string; icon: string } | null)[])
    .filter((x): x is { label: string; name: string; date: string; icon: string } => x !== null)
    .sort((a, b) => a.date.localeCompare(b.date))

  // Profile form
  let pName = ''; let pBreed = ''; let pBirth = ''; let pWeight = ''; let pNotes = ''
  let pAnimalType = 'cat'; let pPhotoUrl = ''; let pCoatColor = ''
  let savingProfile = false; let uploadingPhoto = false; let saveError = ''

  // Vaccine form
  let showVaccModal = false; let editingVacc: CatVaccine | null = null
  let vName = ''; let vDate = ''; let vNextDue = ''; let vClinic = ''; let vNotes = ''
  let savingVacc = false

  // Health form
  let showHealthModal = false; let editingHealth: CatHealthEvent | null = null
  let hDate = ''; let hDesc = ''; let hVet = false; let hCategory = 'vet'; let hDetails = ''
  let savingHealth = false

  // Grooming form
  let showGroomModal = false; let editingGroom: CatGrooming | null = null
  let gDate = ''; let gType = 'Грумер'; let gNextDue = ''; let gNotes = ''
  let savingGroom = false

  // Food form
  let showFoodModal = false; let editingFood: CatFoodOrder | null = null
  let fDate = ''; let fBrand = ''; let fProduct = ''; let fQty = ''; let fPrice = ''; let fNext = ''
  let savingFood = false

  async function load() {
    if (!$user) return
    const { data, error } = await supabase.from('cat_profiles').select('*').eq('user_id', $user.id).order('name')
    if (error) { loadError = error.message; loading = false; return }
    profiles = data ?? []
    if (profiles.length === 1) await openPet(profiles[0])
    else if (profiles.length > 1) showPetPicker = true
    loading = false
  }

  function fillForm(p: CatProfile) {
    pName = p.name; pBreed = p.breed ?? ''; pBirth = p.birth_date ?? ''
    pWeight = p.weight_kg?.toString() ?? ''; pNotes = p.notes ?? ''
    pAnimalType = p.animal_type ?? 'cat'; pPhotoUrl = p.photo_url ?? ''
    pCoatColor = p.coat_color ?? ''; saveError = ''
  }

  async function openPet(p: CatProfile) {
    showPetPicker = false
    selectedProfile = p; fillForm(p); catSection = null
    await loadPetData(p.id); view = 'pet'
  }

  function startNewPet() {
    showPetPicker = false
    selectedProfile = null; pName = ''; pBreed = ''; pBirth = ''; pWeight = ''; pNotes = ''
    pAnimalType = 'cat'; pPhotoUrl = ''; pCoatColor = ''; saveError = ''; isNewPet = true
    vaccines = []; healthEvents = []; groomings = []; foodOrders = []
    catSection = null; showProfileEdit = true; view = 'pet'
  }

  function goBack() { view = 'list'; selectedProfile = null; isNewPet = false; showPetPicker = profiles.length > 1 }

  async function loadPetData(catId: string) {
    const [vaccRes, healthRes, groomRes, foodRes] = await Promise.all([
      supabase.from('cat_vaccines').select('*').eq('cat_id', catId).order('date', { ascending: false }),
      supabase.from('cat_health_events').select('*').eq('cat_id', catId).order('date', { ascending: false }),
      supabase.from('cat_groomings').select('*').eq('cat_id', catId).order('date', { ascending: false }),
      supabase.from('cat_food_orders').select('*').eq('cat_id', catId).order('date', { ascending: false }),
    ])
    vaccines = vaccRes.data ?? []; healthEvents = healthRes.data ?? []
    groomings = groomRes.data ?? []; foodOrders = foodRes.data ?? []
  }

  async function handlePhotoChange(e: Event) {
    const file = (e.target as HTMLInputElement).files?.[0]
    if (!file || !$user) return
    uploadingPhoto = true
    const ext = file.name.split('.').pop() ?? 'jpg'
    const petId = selectedProfile?.id ?? `new-${Date.now()}`
    const path = `${$user.id}/${petId}.${ext}`
    const { error } = await supabase.storage.from('pet-photos').upload(path, file, { upsert: true })
    if (!error) {
      const { data } = supabase.storage.from('pet-photos').getPublicUrl(path)
      pPhotoUrl = data.publicUrl
      if (selectedProfile) {
        await supabase.from('cat_profiles').update({ photo_url: pPhotoUrl }).eq('id', selectedProfile.id)
        selectedProfile = { ...selectedProfile, photo_url: pPhotoUrl }
        profiles = profiles.map(p => p.id === selectedProfile!.id ? selectedProfile! : p)
      }
    }
    uploadingPhoto = false
  }

  async function saveProfile() {
    if (!$user || !pName.trim()) return
    savingProfile = true; saveError = ''
    const payload = { user_id: $user.id, name: pName.trim(), breed: pBreed || null, birth_date: pBirth || null, weight_kg: pWeight ? parseFloat(pWeight) : null, notes: pNotes || null, animal_type: pAnimalType, photo_url: pPhotoUrl || null, coat_color: pCoatColor || null }
    if (selectedProfile) {
      const { data, error } = await supabase.from('cat_profiles').update(payload).eq('id', selectedProfile.id).select().single()
      if (error) { saveError = error.message; showToast(error.message, 'error') }
      else if (data) { selectedProfile = data; profiles = profiles.map(p => p.id === data.id ? data : p); showToast('Сохранено'); showProfileEdit = false }
    } else {
      const { data, error } = await supabase.from('cat_profiles').insert(payload).select().single()
      if (error) { saveError = error.message; showToast(error.message, 'error') }
      else if (data) { profiles = [...profiles, data]; selectedProfile = data; isNewPet = false; showToast('Питомец добавлен'); showProfileEdit = false }
    }
    savingProfile = false
  }

  async function deletePet() {
    if (!selectedProfile) return
    await supabase.from('cat_profiles').delete().eq('id', selectedProfile.id)
    profiles = profiles.filter(p => p.id !== selectedProfile!.id)
    showProfileEdit = false; goBack()
  }

  // Vaccines
  function openVacc(v?: CatVaccine) {
    editingVacc = v ?? null; vName = v?.name ?? ''; vDate = v?.date ?? ''
    vNextDue = v?.next_due ?? ''; vClinic = v?.clinic ?? ''; vNotes = v?.notes ?? ''
    showVaccModal = true
  }
  async function saveVaccine() {
    if (!$user || !selectedProfile || !vName.trim() || !vDate) return
    savingVacc = true
    const payload = { user_id: $user.id, cat_id: selectedProfile.id, name: vName.trim(), date: vDate, next_due: vNextDue || null, clinic: vClinic || null, notes: vNotes || null }
    if (editingVacc) {
      const { data } = await supabase.from('cat_vaccines').update(payload).eq('id', editingVacc.id).select().single()
      if (data) { vaccines = vaccines.map(v => v.id === editingVacc!.id ? data : v); showToast('Сохранено') }
    } else {
      const { data } = await supabase.from('cat_vaccines').insert(payload).select().single()
      if (data) { vaccines = [data, ...vaccines]; showToast('Прививка добавлена') }
    }
    showVaccModal = false; savingVacc = false
  }

  // Health
  function openHealth(e?: CatHealthEvent) {
    editingHealth = e ?? null; hDate = e?.date ?? ''; hDesc = e?.description ?? ''
    hVet = e?.vet_visit ?? false; hCategory = e?.category ?? 'vet'; hDetails = ''
    showHealthModal = true
  }
  async function saveHealthEvent() {
    if (!$user || !selectedProfile || !hDesc.trim() || !hDate) return
    savingHealth = true
    const payload = { user_id: $user.id, cat_id: selectedProfile.id, date: hDate, description: hDesc.trim(), vet_visit: hCategory === 'vet', category: hCategory }
    if (editingHealth) {
      const { data } = await supabase.from('cat_health_events').update(payload).eq('id', editingHealth.id).select().single()
      if (data) { healthEvents = healthEvents.map(e => e.id === editingHealth!.id ? data : e); showToast('Сохранено') }
    } else {
      const { data } = await supabase.from('cat_health_events').insert(payload).select().single()
      if (data) { healthEvents = [data, ...healthEvents]; showToast('Запись добавлена') }
    }
    showHealthModal = false; savingHealth = false
  }

  // Grooming
  function openGroom(g?: CatGrooming) {
    editingGroom = g ?? null; gDate = g?.date ?? ''; gType = g?.type ?? 'Грумер'
    gNextDue = g?.next_due ?? ''; gNotes = g?.notes ?? ''; showGroomModal = true
  }
  async function saveGrooming() {
    if (!$user || !selectedProfile || !gDate) return
    savingGroom = true
    const payload = { user_id: $user.id, cat_id: selectedProfile.id, date: gDate, type: gType, next_due: gNextDue || null, notes: gNotes || null }
    if (editingGroom) {
      const { data } = await supabase.from('cat_groomings').update(payload).eq('id', editingGroom.id).select().single()
      if (data) { groomings = groomings.map(g => g.id === editingGroom!.id ? data : g); showToast('Сохранено') }
    } else {
      const { data } = await supabase.from('cat_groomings').insert(payload).select().single()
      if (data) { groomings = [data, ...groomings]; showToast('Запись добавлена') }
    }
    showGroomModal = false; savingGroom = false
  }

  // Food
  function openFood(f?: CatFoodOrder) {
    editingFood = f ?? null; fDate = f?.date ?? ''; fBrand = f?.brand ?? ''; fProduct = f?.product ?? ''
    fQty = f?.quantity ?? ''; fPrice = f?.price?.toString() ?? ''; fNext = f?.next_order ?? ''
    showFoodModal = true
  }
  async function saveFoodOrder() {
    if (!$user || !selectedProfile || !fBrand.trim() || !fDate) return
    savingFood = true
    const payload = { user_id: $user.id, cat_id: selectedProfile.id, date: fDate, brand: fBrand.trim(), product: fProduct || fBrand.trim(), quantity: fQty || null, price: fPrice ? parseFloat(fPrice) : null, next_order: fNext || null }
    if (editingFood) {
      const { data } = await supabase.from('cat_food_orders').update(payload).eq('id', editingFood.id).select().single()
      if (data) { foodOrders = foodOrders.map(f => f.id === editingFood!.id ? data : f); showToast('Сохранено') }
    } else {
      const { data } = await supabase.from('cat_food_orders').insert(payload).select().single()
      if (data) { foodOrders = [data, ...foodOrders]; showToast('Заказ добавлен') }
    }
    showFoodModal = false; savingFood = false
  }

  async function deleteRow(table: string, id: string, arr: string) {
    await supabase.from(table).delete().eq('id', id)
    if (arr === 'vaccines') vaccines = vaccines.filter(v => v.id !== id)
    else if (arr === 'health') healthEvents = healthEvents.filter(e => e.id !== id)
    else if (arr === 'groomings') groomings = groomings.filter(g => g.id !== id)
    else if (arr === 'food') foodOrders = foodOrders.filter(f => f.id !== id)
  }

  const RU_MONTHS = ['янв.','фев.','мар.','апр.','мая','июн.','июл.','авг.','сен.','окт.','ноя.','дек.']
  function fmt(d: string | null | undefined): string {
    if (!d) return ''
    const parts = d.split('-')
    if (parts.length < 3) return ''
    return `${parseInt(parts[2])} ${RU_MONTHS[parseInt(parts[1]) - 1]}`
  }
  function fmtFull(d: string | null | undefined): string {
    if (!d) return ''
    const parts = d.split('-')
    if (parts.length < 3) return ''
    return `${parseInt(parts[2])} ${RU_MONTHS[parseInt(parts[1]) - 1]} ${parts[0]} г.`
  }

  onMount(load)
</script>

<div class="page-shell">
  {#if loadError}
    <div class="load-error mt-4">Ошибка загрузки: {loadError}</div>

  {:else if loading}
    <div class="skeleton mt-4" style="height:10rem" />

  {:else if view === 'list'}
    <!-- LANDING -->
    <header class="page-header">
      <h1 class="section-title">Животные</h1>
      <button class="add-btn" on:click={startNewPet}>+ Добавить</button>
    </header>
    {#if profiles.length === 0}
      <div class="empty-state mt-4">
        <div class="empty-icon">{@html icons.paw}</div>
        <p>Добавь первого питомца</p>
        <button class="btn-primary" style="margin-top:1rem" on:click={startNewPet}>Добавить питомца</button>
      </div>
    {:else}
      <div class="pet-grid">
        {#each profiles as p}
          <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
          <div class="pet-card" on:click={() => openPet(p)}>
            <div class="pet-avatar">
              {#if p.photo_url}
                <img src={p.photo_url} alt={p.name} class="pet-img" />
              {:else}
                <div class="pet-icon-wrap">{@html icons.paw}</div>
              {/if}
            </div>
            <div class="pet-card-info">
              <span class="pet-card-name">{p.name}</span>
              {#if p.breed}<span class="pet-card-sub">{p.breed}</span>{/if}
              {#if p.coat_color}<span class="pet-card-sub">{p.coat_color}</span>{/if}
              {#if petAge(p.birth_date)}<span class="pet-card-age">{petAge(p.birth_date)}</span>{/if}
            </div>
          </div>
        {/each}
      </div>
    {/if}

  {:else if selectedProfile || isNewPet}
    <!-- PET PROFILE -->

    {#if catSection === null}
      <!-- HUB -->
      <header class="pet-hub-header">
        <button class="back-btn" on:click={goBack}>
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75"><path d="M19 12H5M12 5l-7 7 7 7"/></svg>
        </button>
        {#if selectedProfile}
          <div class="pet-hero">
            <div class="pet-avatar-sm">
              {#if selectedProfile.photo_url}
                <img src={selectedProfile.photo_url} alt={selectedProfile.name} class="pet-img" />
              {:else}
                <div class="pet-icon-sm">{@html icons.paw}</div>
              {/if}
            </div>
            <div class="pet-hero-info">
              <span class="pet-hero-name">{selectedProfile.name}</span>
              <span class="pet-hero-sub">
                {[selectedProfile.breed, selectedProfile.coat_color].filter(Boolean).join(' · ')}
              </span>
              {#if petAge(selectedProfile.birth_date) || selectedProfile.weight_kg}
                <span class="pet-hero-meta">
                  {[petAge(selectedProfile.birth_date), selectedProfile.weight_kg ? selectedProfile.weight_kg + ' кг' : null].filter(Boolean).join(' · ')}
                </span>
              {/if}
            </div>
          </div>
          <div class="pet-header-actions">
            {#if profiles.length > 1}
              <button class="gear-btn" on:click={() => showPetPicker = true} title="Сменить питомца">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75"><path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 00-3-3.87M16 3.13a4 4 0 010 7.75"/></svg>
              </button>
            {/if}
          <button class="gear-btn" on:click={() => { if (selectedProfile) fillForm(selectedProfile); showProfileEdit = true }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 15a3 3 0 100-6 3 3 0 000 6z"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-2 2 2 2 0 01-2-2v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 01-2-2 2 2 0 012-2h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 012.83-2.83l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 012-2 2 2 0 012 2v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 012 2 2 2 0 01-2 2h-.09a1.65 1.65 0 00-1.51 1z"/></svg>
          </button>
          </div>
        {/if}
      </header>

      <!-- Section grid -->
      <div class="sections-grid">
        <button class="section-card" on:click={() => { catSection = 'vaccines'; showArchived = false }}>
          <div class="section-card-icon">{@html icons.pill}</div>
          <span class="section-card-label">Прививки</span>
          <span class="section-card-count">{vaccines.length}</span>
          {#if nextVaccine}<span class="section-card-hint">след. {fmt(nextVaccine.next_due)}</span>{/if}
        </button>
        <button class="section-card" on:click={() => { catSection = 'grooming'; showArchived = false }}>
          <div class="section-card-icon">{@html icons.scissors}</div>
          <span class="section-card-label">Уход</span>
          <span class="section-card-count">{groomings.length}</span>
          {#if nextGroom}<span class="section-card-hint">след. {fmt(nextGroom.next_due)}</span>{/if}
        </button>
        <button class="section-card" on:click={() => { catSection = 'health'; showArchived = false }}>
          <div class="section-card-icon">{@html icons.stethoscope}</div>
          <span class="section-card-label">Здоровье</span>
          <span class="section-card-count">{healthEvents.length}</span>
        </button>
        <button class="section-card" on:click={() => { catSection = 'food'; showArchived = false }}>
          <div class="section-card-icon">{@html icons.bowl}</div>
          <span class="section-card-label">Корм</span>
          <span class="section-card-count">{foodOrders.length}</span>
          {#if nextFood}<span class="section-card-hint">след. {fmt(nextFood.next_order)}</span>{/if}
        </button>
      </div>

      <!-- Upcoming (sorted by nearest date) -->
      {#if upcomingItems.length > 0}
        <section class="upcoming-section">
          <p class="label mb-2">Ближайшее</p>
          <div class="upcoming-list">
            {#each upcomingItems as item}
              <div class="upcoming-item">
                <div class="upcoming-icon">{@html item.icon}</div>
                <div class="upcoming-info">
                  <span class="upcoming-type">{item.label}</span>
                  <span class="upcoming-name">{item.name}</span>
                </div>
                <span class="upcoming-date">{fmt(item.date)}</span>
              </div>
            {/each}
          </div>
        </section>
      {/if}

    {:else}
      <!-- SECTION VIEW -->
      <header class="section-header-row">
        <button class="back-btn" on:click={() => catSection = null}>
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75"><path d="M19 12H5M12 5l-7 7 7 7"/></svg>
        </button>
        <h1 class="section-title">
          {catSection === 'vaccines' ? 'Прививки' : catSection === 'health' ? 'Здоровье' : catSection === 'grooming' ? 'Уход' : 'Корм'}
        </h1>
        <button class="add-btn" on:click={() => {
          if (catSection === 'vaccines') openVacc()
          else if (catSection === 'health') openHealth()
          else if (catSection === 'grooming') openGroom()
          else openFood()
        }}>+ Добавить</button>
      </header>

      <!-- VACCINES -->
      {#if catSection === 'vaccines'}
        {#if vaccines.length === 0}
          <div class="empty-state mt-3">Прививок пока нет</div>
        {:else}
          {@const archivedCount = sortedVaccines.filter(v => recState(v, 'next_due') === 'past').length}
          <div class="item-list mt-3">
            {#each sortedVaccines as v}
              {@const st = recState(v, 'next_due')}
              {#if st !== 'past' || showArchived}
                <div class="item-card" class:item-dim={st === 'recent'}>
                  <div class="item-row">
                    <div class="item-main">
                      <span class="item-title" class:item-strike={st === 'recent'}>{v.name}</span>
                      <span class="item-date">{fmtFull(v.date)}</span>
                      {#if v.next_due}<span class="item-next">{st === 'recent' ? 'Была: ' : 'Следующая: '}{fmtFull(v.next_due)}</span>{/if}
                      {#if v.clinic}<span class="item-sub">{v.clinic}</span>{/if}
                    </div>
                    <div class="item-btns">
                      <button class="edit-btn" on:click={() => openVacc(v)}>Изм.</button>
                      <button class="del-btn" on:click={() => deleteRow('cat_vaccines', v.id, 'vaccines')}>×</button>
                    </div>
                  </div>
                </div>
              {/if}
            {/each}
          </div>
          {#if archivedCount > 0}
            <button class="archive-toggle mt-3" on:click={() => showArchived = !showArchived}>
              {showArchived ? 'Скрыть архив' : `Архив (${archivedCount})`}
            </button>
          {/if}
        {/if}
      {/if}

      <!-- HEALTH -->
      {#if catSection === 'health'}
        <div class="filter-row mt-2">
          <button class="filter-btn" class:active={healthFilter === null} on:click={() => healthFilter = null}>Все</button>
          {#each HEALTH_CATEGORIES as c}
            <button class="filter-btn" class:active={healthFilter === c.id} on:click={() => healthFilter = healthFilter === c.id ? null : c.id}>
              <span class="filter-btn-icon">{@html c.icon}</span>{c.label}
            </button>
          {/each}
        </div>
        {#if filteredHealth.length === 0}
          <div class="empty-state mt-3">Записей нет</div>
        {:else}
          {@const archivedCount = sortedHealth.filter(e => recState(e) === 'past').length}
          <div class="item-list mt-3">
            {#each sortedHealth as e}
              {@const st = recState(e)}
              {#if st !== 'past' || showArchived}
                <div class="item-card" class:item-dim={st === 'recent'}>
                  <div class="item-row">
                    <div class="item-category-badge cat-{e.category}">
                      <span class="cat-badge-icon">{@html categoryFor(e.category).icon}</span>
                    </div>
                    <div class="item-main">
                      <div class="item-title-row">
                        <span class="item-title" class:item-strike={st === 'recent'}>{e.description}</span>
                        <span class="item-category-label">{categoryFor(e.category).label}</span>
                      </div>
                      <span class="item-date">{fmtFull(e.date)}</span>
                    </div>
                    <div class="item-btns">
                      <button class="edit-btn" on:click={() => openHealth(e)}>Изм.</button>
                      <button class="del-btn" on:click={() => deleteRow('cat_health_events', e.id, 'health')}>×</button>
                    </div>
                  </div>
                </div>
              {/if}
            {/each}
          </div>
          {#if archivedCount > 0}
            <button class="archive-toggle mt-3" on:click={() => showArchived = !showArchived}>
              {showArchived ? 'Скрыть архив' : `Архив (${archivedCount})`}
            </button>
          {/if}
        {/if}
      {/if}

      <!-- GROOMING -->
      {#if catSection === 'grooming'}
        {#if groomings.length > 0}
          <div class="filter-row mt-2">
            <button class="filter-btn" class:active={groomingFilter === null} on:click={() => groomingFilter = null}>Все</button>
            {#each GROOM_TYPES as t}
              {#if groomings.some(g => g.type === t)}
                <button class="filter-btn" class:active={groomingFilter === t} on:click={() => groomingFilter = groomingFilter === t ? null : t}>{t}</button>
              {/if}
            {/each}
          </div>
        {/if}
        {#if filteredGroomings.length === 0}
          <div class="empty-state mt-3">Визитов пока нет</div>
        {:else}
          {@const archivedCount = sortedGroomings.filter(g => recState(g, 'next_due') === 'past').length}
          <div class="item-list mt-3">
            {#each sortedGroomings as g}
              {@const st = recState(g, 'next_due')}
              {#if st !== 'past' || showArchived}
                <div class="item-card" class:item-dim={st === 'recent'}>
                  <div class="item-row">
                    <div class="item-main">
                      <span class="item-title" class:item-strike={st === 'recent'}>{g.type}</span>
                      <span class="item-date">{fmtFull(g.date)}</span>
                      {#if g.next_due}<span class="item-next">{st === 'recent' ? 'Был: ' : 'Следующий: '}{fmtFull(g.next_due)}</span>{/if}
                      {#if g.notes}<span class="item-sub">{g.notes}</span>{/if}
                    </div>
                    <div class="item-btns">
                      <button class="edit-btn" on:click={() => openGroom(g)}>Изм.</button>
                      <button class="del-btn" on:click={() => deleteRow('cat_groomings', g.id, 'groomings')}>×</button>
                    </div>
                  </div>
                </div>
              {/if}
            {/each}
          </div>
          {#if archivedCount > 0}
            <button class="archive-toggle mt-3" on:click={() => showArchived = !showArchived}>
              {showArchived ? 'Скрыть архив' : `Архив (${archivedCount})`}
            </button>
          {/if}
        {/if}
      {/if}

      <!-- FOOD -->
      {#if catSection === 'food'}
        {#if foodBrands.length > 1}
          <div class="filter-row mt-2">
            <button class="filter-btn" class:active={foodBrandFilter === null} on:click={() => foodBrandFilter = null}>Все</button>
            {#each foodBrands as b}
              <button class="filter-btn" class:active={foodBrandFilter === b} on:click={() => foodBrandFilter = foodBrandFilter === b ? null : b}>{b}</button>
            {/each}
          </div>
        {/if}
        {#if filteredFood.length === 0}
          <div class="empty-state mt-3">Заказов пока нет</div>
        {:else}
          {@const archivedCount = sortedFood.filter(f => recState(f, 'next_order') === 'past').length}
          <div class="item-list mt-3">
            {#each sortedFood as f}
              {@const st = recState(f, 'next_order')}
              {#if st !== 'past' || showArchived}
                <div class="item-card" class:item-dim={st === 'recent'}>
                  <div class="item-row">
                    <div class="item-main">
                      <span class="item-title" class:item-strike={st === 'recent'}>{f.brand} — {f.product}</span>
                      <span class="item-date">{fmtFull(f.date)}{f.quantity ? ' · ' + f.quantity : ''}{f.price ? ' · ' + f.price.toLocaleString('ru') + ' ₽' : ''}</span>
                      {#if f.next_order}<span class="item-next">{st === 'recent' ? 'Был: ' : 'Следующий: '}{fmtFull(f.next_order)}</span>{/if}
                    </div>
                    <div class="item-btns">
                      <button class="edit-btn" on:click={() => openFood(f)}>Изм.</button>
                      <button class="del-btn" on:click={() => deleteRow('cat_food_orders', f.id, 'food')}>×</button>
                    </div>
                  </div>
                </div>
              {/if}
            {/each}
          </div>
          {#if archivedCount > 0}
            <button class="archive-toggle mt-3" on:click={() => showArchived = !showArchived}>
              {showArchived ? 'Скрыть архив' : `Архив (${archivedCount})`}
            </button>
          {/if}
        {/if}
      {/if}
    {/if}
  {/if}
</div>

<!-- Pet picker bottom sheet -->
{#if showPetPicker}
  <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
  <div class="picker-backdrop" on:click={() => { if (profiles.length > 0 && selectedProfile) showPetPicker = false }}></div>
  <div class="picker-sheet">
    <div class="picker-handle"></div>
    <h2 class="picker-title">Выбери питомца</h2>
    <div class="picker-pets">
      {#each profiles as p}
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="picker-pet" on:click={() => openPet(p)}>
          <div class="picker-avatar">
            {#if p.photo_url}
              <img src={p.photo_url} alt={p.name} class="pet-img" />
            {:else}
              <div class="picker-icon">{@html icons.paw}</div>
            {/if}
          </div>
          <span class="picker-pet-name">{p.name}</span>
          {#if p.breed}<span class="picker-pet-sub">{p.breed}</span>{/if}
        </div>
      {/each}
    </div>
    <button class="picker-add-btn" on:click={startNewPet}>
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14M5 12h14"/></svg>
      Добавить питомца
    </button>
  </div>
{/if}

<!-- Profile edit modal -->
<Modal title={isNewPet ? 'Новый питомец' : 'Редактировать профиль'} open={showProfileEdit} on:close={() => showProfileEdit = false}>
  <div class="form-stack">
    <div class="photo-field">
      <div class="photo-preview-wrap">
        {#if pPhotoUrl}
          <img src={pPhotoUrl} alt="Фото" class="photo-preview" />
        {:else}
          <div class="photo-placeholder-icon">{@html icons.paw}</div>
        {/if}
      </div>
      <label class="photo-upload-btn">
        {uploadingPhoto ? 'Загружаю...' : 'Загрузить фото'}
        <input type="file" accept="image/*" on:change={handlePhotoChange} style="display:none" disabled={uploadingPhoto} />
      </label>
    </div>
    <div class="form-field">
      <label class="label">Тип животного</label>
      <div class="animal-type-row">
        {#each ANIMAL_TYPES as t}
          <button class="animal-type-btn" class:selected={pAnimalType === t.id} on:click={() => pAnimalType = t.id}>
            {t.label}
          </button>
        {/each}
      </div>
    </div>
    <div class="form-field">
      <label class="label" for="p-name">Имя</label>
      <input id="p-name" type="text" bind:value={pName} placeholder="Имя питомца" />
    </div>
    {#if breedsFor(pAnimalType).length > 0}
      <div class="form-field">
        <label class="label">Порода</label>
        <div class="chip-grid">
          {#each breedsFor(pAnimalType) as b}
            <button class="chip" class:selected={pBreed === b} on:click={() => pBreed = pBreed === b ? '' : b}>{b}</button>
          {/each}
        </div>
      </div>
    {:else}
      <div class="form-field">
        <label class="label" for="p-breed">Порода</label>
        <input id="p-breed" type="text" bind:value={pBreed} placeholder="Необязательно" />
      </div>
    {/if}
    {#if colorsFor(pAnimalType).length > 0}
      <div class="form-field">
        <label class="label">Окрас</label>
        <div class="chip-grid">
          {#each colorsFor(pAnimalType) as c}
            <button class="chip" class:selected={pCoatColor === c} on:click={() => pCoatColor = pCoatColor === c ? '' : c}>{c}</button>
          {/each}
        </div>
      </div>
    {/if}
    <div class="form-field">
      <label class="label" for="p-birth">Дата рождения</label>
      <input id="p-birth" type="date" bind:value={pBirth} />
    </div>
    <div class="form-field">
      <label class="label" for="p-weight">Вес (кг)</label>
      <input id="p-weight" type="number" bind:value={pWeight} placeholder="4.2" step="0.1" inputmode="decimal" />
    </div>
    <div class="form-field">
      <label class="label" for="p-notes">Заметки</label>
      <textarea id="p-notes" bind:value={pNotes} rows="2" placeholder="Особенности, диета..." />
    </div>
    {#if saveError}<p class="save-error">{saveError}</p>{/if}
    <button class="btn-primary" on:click={saveProfile} disabled={savingProfile || !pName.trim()}>
      {savingProfile ? 'Сохраняю...' : selectedProfile ? 'Обновить' : 'Создать профиль'}
    </button>
    {#if selectedProfile}
      <button class="btn-ghost" style="color:#ef4444;margin-top:-0.5rem" on:click={deletePet}>Удалить питомца</button>
    {/if}
  </div>
</Modal>

<!-- Vaccine modal -->
<Modal title={editingVacc ? 'Редактировать' : 'Прививка'} open={showVaccModal} on:close={() => showVaccModal = false}>
  <div class="form-stack">
    <div class="form-field"><label class="label" for="v-name">Название</label>
      <input id="v-name" type="text" bind:value={vName} placeholder="Комплексная, Бешенство..." /></div>
    <div class="form-field"><label class="label" for="v-date">Дата</label>
      <input id="v-date" type="date" bind:value={vDate} /></div>
    <div class="form-field"><label class="label" for="v-next">Следующая</label>
      <input id="v-next" type="date" bind:value={vNextDue} /></div>
    <div class="form-field"><label class="label" for="v-clinic">Клиника</label>
      <input id="v-clinic" type="text" bind:value={vClinic} placeholder="Необязательно" /></div>
    <button class="btn-primary" on:click={saveVaccine} disabled={savingVacc || !vName.trim() || !vDate}>
      {savingVacc ? 'Сохраняю...' : editingVacc ? 'Обновить' : 'Добавить'}</button>
  </div>
</Modal>

<!-- Health modal -->
<Modal title={editingHealth ? 'Редактировать' : 'Запись о здоровье'} open={showHealthModal} on:close={() => showHealthModal = false}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label">Категория</label>
      <div class="health-cat-row">
        {#each HEALTH_CATEGORIES as c}
          <button class="health-cat-btn" class:selected={hCategory === c.id} on:click={() => hCategory = c.id}>
            <span class="cat-btn-icon">{@html c.icon}</span>{c.label}
          </button>
        {/each}
      </div>
    </div>
    <div class="form-field"><label class="label" for="h-date">Дата</label>
      <input id="h-date" type="date" bind:value={hDate} /></div>
    <div class="form-field"><label class="label" for="h-desc">Описание</label>
      <textarea id="h-desc" bind:value={hDesc} rows="3" placeholder="Что случилось? Симптомы, результаты..." /></div>
    <button class="btn-primary" on:click={saveHealthEvent} disabled={savingHealth || !hDesc.trim() || !hDate}>
      {savingHealth ? 'Сохраняю...' : editingHealth ? 'Обновить' : 'Добавить'}</button>
  </div>
</Modal>

<!-- Grooming modal -->
<Modal title={editingGroom ? 'Редактировать' : 'Уход'} open={showGroomModal} on:close={() => showGroomModal = false}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label">Тип</label>
      <div class="radio-group">
        {#each GROOM_TYPES as t}
          <label class="radio-pill" class:selected={gType === t}><input type="radio" bind:group={gType} value={t} />{t}</label>
        {/each}
      </div>
    </div>
    <div class="form-field"><label class="label" for="g-date">Дата</label>
      <input id="g-date" type="date" bind:value={gDate} /></div>
    <div class="form-field"><label class="label" for="g-next">Следующий визит</label>
      <input id="g-next" type="date" bind:value={gNextDue} /></div>
    <div class="form-field"><label class="label" for="g-notes">Заметка</label>
      <input id="g-notes" type="text" bind:value={gNotes} placeholder="Необязательно" /></div>
    <button class="btn-primary" on:click={saveGrooming} disabled={savingGroom || !gDate}>
      {savingGroom ? 'Сохраняю...' : editingGroom ? 'Обновить' : 'Добавить'}</button>
  </div>
</Modal>

<!-- Food modal -->
<Modal title={editingFood ? 'Редактировать' : 'Заказ корма'} open={showFoodModal} on:close={() => showFoodModal = false}>
  <div class="form-stack">
    <div class="form-field"><label class="label" for="f-brand">Бренд</label>
      <input id="f-brand" type="text" bind:value={fBrand} placeholder="Royal Canin, Purina..." /></div>
    <div class="form-field"><label class="label" for="f-product">Продукт</label>
      <input id="f-product" type="text" bind:value={fProduct} placeholder="Sterilised, Indoor..." /></div>
    <div class="form-field"><label class="label" for="f-date">Дата заказа</label>
      <input id="f-date" type="date" bind:value={fDate} /></div>
    <div class="form-row">
      <div class="form-field"><label class="label" for="f-qty">Количество</label>
        <input id="f-qty" type="text" bind:value={fQty} placeholder="2 кг" /></div>
      <div class="form-field"><label class="label" for="f-price">Цена ₽</label>
        <input id="f-price" type="number" bind:value={fPrice} placeholder="1200" inputmode="numeric" /></div>
    </div>
    <div class="form-field"><label class="label" for="f-next">Следующий заказ</label>
      <input id="f-next" type="date" bind:value={fNext} /></div>
    <button class="btn-primary" on:click={saveFoodOrder} disabled={savingFood || !fBrand.trim() || !fDate}>
      {savingFood ? 'Сохраняю...' : editingFood ? 'Обновить' : 'Добавить'}</button>
  </div>
</Modal>

<style>
  .page-header { display: flex; align-items: center; gap: 0.75rem; padding: 1rem 0 0.75rem; }
  .section-title { flex: 1; }
  .add-btn { background: var(--color-accent); color: white; border: none; border-radius: 0.875rem; padding: 0.5rem 1rem; font-size: 0.875rem; cursor: pointer; flex-shrink: 0; -webkit-tap-highlight-color: transparent; }
  .back-btn { background: none; border: none; color: var(--color-text); cursor: pointer; padding: 0.25rem; display: flex; align-items: center; flex-shrink: 0; -webkit-tap-highlight-color: transparent; }

  /* Pet hub header */
  .pet-hub-header { display: flex; align-items: center; gap: 0.75rem; padding: 1rem 0 1rem; }
  .pet-hero { flex: 1; display: flex; align-items: center; gap: 0.75rem; min-width: 0; }
  .pet-avatar-sm { width: 3.5rem; height: 3.5rem; border-radius: 50%; background: var(--color-card); border: 1px solid var(--color-border); overflow: hidden; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
  .pet-icon-sm { color: var(--color-accent); width: 1.5rem; height: 1.5rem; }
  .pet-icon-sm :global(svg) { width: 100%; height: 100%; }
  .pet-hero-info { display: flex; flex-direction: column; gap: 1px; min-width: 0; }
  .pet-hero-name { font-size: 1.125rem; font-weight: 500; color: var(--color-text); }
  .pet-hero-sub { font-size: 0.8125rem; color: var(--color-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .pet-hero-meta { font-size: 0.75rem; color: var(--color-accent); font-family: "JetBrains Mono", monospace; }
  .gear-btn { background: none; border: none; color: var(--color-muted); cursor: pointer; padding: 0.25rem; display: flex; align-items: center; flex-shrink: 0; -webkit-tap-highlight-color: transparent; }
  .gear-btn:active { opacity: 0.6; }

  /* Section grid */
  .sections-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0.625rem; margin-bottom: 1.25rem; }
  .section-card { background: var(--color-card); border: 1px solid var(--color-border); border-radius: 1.25rem; padding: 1rem; cursor: pointer; display: flex; flex-direction: column; align-items: flex-start; gap: 0.25rem; text-align: left; -webkit-tap-highlight-color: transparent; transition: opacity 0.15s; }
  .section-card:active { opacity: 0.7; }
  .section-card-icon { width: 2rem; height: 2rem; background: var(--color-bg); border: 1px solid var(--color-border); border-radius: 0.625rem; display: flex; align-items: center; justify-content: center; color: var(--color-accent); padding: 0.375rem; margin-bottom: 0.25rem; flex-shrink: 0; }
  .section-card-icon :global(svg) { width: 100%; height: 100%; }
  .section-card-label { font-size: 0.9375rem; color: var(--color-text); font-weight: 500; }
  .section-card-count { font-family: "JetBrains Mono", monospace; font-size: 1.25rem; color: var(--color-accent); line-height: 1; }
  .section-card-hint { font-size: 0.75rem; color: var(--color-muted); }

  /* Upcoming */
  .upcoming-section { margin-top: 0.25rem; }
  .upcoming-list { display: flex; flex-direction: column; gap: 0.375rem; }
  .upcoming-item { display: flex; align-items: center; gap: 0.625rem; padding: 0.625rem 0.875rem; background: var(--color-card); border: 1px solid var(--color-border); border-radius: 0.875rem; }
  .upcoming-icon { width: 1.25rem; height: 1.25rem; color: var(--color-muted); flex-shrink: 0; }
  .upcoming-icon :global(svg) { width: 100%; height: 100%; }
  .upcoming-info { flex: 1; display: flex; flex-direction: column; gap: 1px; min-width: 0; }
  .upcoming-type { font-size: 0.6875rem; color: var(--color-muted); text-transform: uppercase; letter-spacing: 0.04em; }
  .upcoming-name { font-size: 0.9375rem; color: var(--color-text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .upcoming-date { font-size: 0.8125rem; color: var(--color-accent); font-family: "JetBrains Mono", monospace; white-space: nowrap; }

  /* Section view header */
  .section-header-row { display: flex; align-items: center; gap: 0.75rem; padding: 1rem 0 0.75rem; }

  /* Filter row (health, grooming, food) */
  .filter-row { display: flex; gap: 0.375rem; overflow-x: auto; scrollbar-width: none; padding-bottom: 0.25rem; }
  .filter-row::-webkit-scrollbar { display: none; }
  .filter-btn { flex: 0 0 auto; display: flex; align-items: center; gap: 0.25rem; padding: 0.375rem 0.75rem; border: 1px solid var(--color-border); border-radius: 2rem; background: var(--color-card); font-size: 0.8125rem; color: var(--color-muted); cursor: pointer; white-space: nowrap; -webkit-tap-highlight-color: transparent; transition: all 0.15s; }
  .filter-btn.active { background: var(--color-accent); border-color: var(--color-accent); color: white; }
  .filter-btn-icon { width: 0.875rem; height: 0.875rem; display: flex; align-items: center; flex-shrink: 0; }
  .filter-btn-icon :global(svg) { width: 100%; height: 100%; }
  .filter-btn.active .filter-btn-icon { color: white; }

  /* Health category badge in list */
  .item-category-badge { width: 2.25rem; height: 2.25rem; border-radius: 0.625rem; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
  .cat-vet      { background: #dbeafe; color: #1d4ed8; }
  .cat-symptom  { background: #fef3c7; color: #b45309; }
  .cat-analysis { background: #d1fae5; color: #047857; }
  .cat-exam     { background: #ede9fe; color: #6d28d9; }
  .cat-badge-icon { width: 1rem; height: 1rem; display: flex; align-items: center; }
  .cat-badge-icon :global(svg) { width: 100%; height: 100%; }
  .item-title-row { display: flex; align-items: baseline; gap: 0.5rem; flex-wrap: wrap; }
  .item-category-label { font-size: 0.75rem; color: var(--color-muted); }

  /* Health form category */
  .health-cat-row { display: flex; flex-wrap: wrap; gap: 0.375rem; }
  .health-cat-btn { display: flex; align-items: center; gap: 0.25rem; padding: 0.375rem 0.75rem; border: 1px solid var(--color-border); border-radius: 2rem; background: var(--color-card); font-size: 0.8125rem; color: var(--color-muted); cursor: pointer; -webkit-tap-highlight-color: transparent; transition: all 0.15s; white-space: nowrap; }
  .health-cat-btn.selected { background: var(--color-accent); border-color: var(--color-accent); color: white; }
  .cat-btn-icon { width: 0.875rem; height: 0.875rem; display: flex; align-items: center; flex-shrink: 0; }
  .cat-btn-icon :global(svg) { width: 100%; height: 100%; }

  /* Landing grid */
  .pet-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 0.75rem; margin-top: 0.5rem; }
  .pet-card { background: var(--color-card); border: 1px solid var(--color-border); border-radius: 1.25rem; padding: 1.25rem 1rem 1rem; cursor: pointer; display: flex; flex-direction: column; align-items: center; gap: 0.75rem; -webkit-tap-highlight-color: transparent; transition: opacity 0.15s; }
  .pet-card:active { opacity: 0.75; }
  .pet-avatar { width: 5rem; height: 5rem; border-radius: 50%; background: var(--color-bg); border: 1px solid var(--color-border); display: flex; align-items: center; justify-content: center; overflow: hidden; flex-shrink: 0; }
  .pet-img { width: 100%; height: 100%; object-fit: cover; }
  .pet-icon-wrap { color: var(--color-accent); width: 2.5rem; height: 2.5rem; }
  .pet-icon-wrap :global(svg) { width: 100%; height: 100%; }
  .pet-card-info { display: flex; flex-direction: column; align-items: center; gap: 2px; text-align: center; }
  .pet-card-name { font-size: 1rem; font-weight: 500; color: var(--color-text); }
  .pet-card-sub { font-size: 0.75rem; color: var(--color-muted); }
  .pet-card-age { font-size: 0.75rem; color: var(--color-accent); font-family: "JetBrains Mono", monospace; }

  /* Records */
  .item-list { display: flex; flex-direction: column; gap: 0.5rem; }
  .item-card { background: var(--color-card); border: 1px solid var(--color-border); border-radius: 1rem; padding: 0.875rem 1rem; }
  .item-dim { opacity: 0.45; }
  .item-strike { text-decoration: line-through; }
  .archive-toggle { background: none; border: none; color: var(--color-muted); font-size: 0.8125rem; cursor: pointer; width: 100%; text-align: center; padding: 0.5rem; -webkit-tap-highlight-color: transparent; }
  .item-row { display: flex; align-items: flex-start; gap: 0.625rem; }
  .item-main { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .item-title { font-size: 0.9375rem; }
  .item-date { font-size: 0.8125rem; color: var(--color-muted); }
  .item-next { font-size: 0.8125rem; color: var(--color-accent); }
  .item-sub { font-size: 0.75rem; color: var(--color-muted); }
  .item-btns { display: flex; align-items: center; gap: 0.25rem; flex-shrink: 0; }
  .edit-btn { background: none; border: none; color: var(--color-accent); font-size: 0.75rem; cursor: pointer; padding: 0.125rem 0.375rem; }
  .del-btn { background: none; border: none; color: var(--color-muted); font-size: 1.25rem; cursor: pointer; padding: 0 0.25rem; line-height: 1; }

  /* Profile form */
  .photo-field { display: flex; align-items: center; gap: 1rem; padding: 0.75rem; background: var(--color-bg); border: 1px solid var(--color-border); border-radius: 1rem; }
  .photo-preview-wrap { width: 4rem; height: 4rem; border-radius: 50%; background: var(--color-card); border: 1px solid var(--color-border); overflow: hidden; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
  .photo-preview { width: 100%; height: 100%; object-fit: cover; }
  .photo-placeholder-icon { color: var(--color-accent); width: 2rem; height: 2rem; }
  .photo-placeholder-icon :global(svg) { width: 100%; height: 100%; }
  .photo-upload-btn { flex: 1; padding: 0.5rem 0.875rem; border: 1px dashed var(--color-border); border-radius: 0.75rem; font-size: 0.875rem; color: var(--color-accent); cursor: pointer; text-align: center; -webkit-tap-highlight-color: transparent; }
  .animal-type-row { display: flex; gap: 0.375rem; flex-wrap: wrap; }
  .animal-type-btn { padding: 0.375rem 0.75rem; border: 1px solid var(--color-border); border-radius: 0.875rem; background: var(--color-card); cursor: pointer; font-size: 0.8125rem; color: var(--color-muted); -webkit-tap-highlight-color: transparent; transition: all 0.15s; white-space: nowrap; }
  .animal-type-btn.selected { border-color: var(--color-accent); background: var(--color-accent); color: white; }
  .chip-grid { display: flex; flex-wrap: wrap; gap: 0.375rem; }
  .chip { padding: 0.375rem 0.75rem; border: 1px solid var(--color-border); border-radius: 2rem; background: var(--color-card); font-size: 0.8125rem; color: var(--color-muted); cursor: pointer; -webkit-tap-highlight-color: transparent; transition: all 0.15s; white-space: nowrap; }
  .chip.selected { background: var(--color-accent); border-color: var(--color-accent); color: white; }

  /* Modals */
  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; flex: 1; }
  .form-row { display: flex; gap: 0.75rem; }
  .radio-group { display: flex; flex-wrap: wrap; gap: 0.375rem; }
  .radio-pill { padding: 0.375rem 0.875rem; border: 1px solid var(--color-border); border-radius: 2rem; font-size: 0.8125rem; cursor: pointer; -webkit-tap-highlight-color: transparent; transition: all 0.15s; }
  .radio-pill.selected { background: var(--color-accent); border-color: var(--color-accent); color: white; }
  .radio-pill input { display: none; }

  .save-error { font-size: 0.8125rem; color: #ef4444; background: rgba(239,68,68,0.08); border-radius: 0.5rem; padding: 0.5rem 0.75rem; margin: 0; }
  .load-error { padding: 1rem; background: rgba(239,68,68,0.08); border: 1px solid rgba(239,68,68,0.3); border-radius: 1rem; color: #ef4444; font-size: 0.875rem; }
  .empty-state { padding: 2.5rem 2rem; text-align: center; color: var(--color-muted); background: var(--color-card); border-radius: 1.25rem; border: 1px dashed var(--color-border); display: flex; flex-direction: column; align-items: center; gap: 0.5rem; }
  .empty-icon { color: var(--color-accent); opacity: 0.4; width: 2.5rem; height: 2.5rem; }
  .empty-icon :global(svg) { width: 100%; height: 100%; }
  .skeleton { border-radius: 1.25rem; background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }
  .mt-2 { margin-top: 0.5rem; }
  .mt-3 { margin-top: 0.75rem; }
  .mt-4 { margin-top: 1rem; }
  .mb-2 { margin-bottom: 0.5rem; }

  /* ── Pet picker ── */
  .picker-backdrop {
    position: fixed; inset: 0; background: rgba(0,0,0,0.4);
    z-index: 100; backdrop-filter: blur(2px);
  }
  .picker-sheet {
    position: fixed; bottom: 0; left: 0; right: 0;
    background: var(--color-bg);
    border-radius: 1.5rem 1.5rem 0 0;
    padding: 0.75rem 1.375rem 3rem;
    z-index: 101;
    animation: slideUp 0.25s ease;
    max-width: 480px; margin: 0 auto;
  }
  @keyframes slideUp { from { transform: translateY(100%); } to { transform: translateY(0); } }
  .picker-handle {
    width: 2.5rem; height: 4px; border-radius: 2px;
    background: var(--color-border); margin: 0 auto 1.25rem;
  }
  .picker-title {
    font-family: "Fraunces", serif; font-size: 1.25rem; font-weight: 300;
    color: var(--color-text); margin: 0 0 1rem; letter-spacing: -0.01em;
  }
  .picker-pets {
    display: flex; gap: 0.75rem; overflow-x: auto;
    -webkit-overflow-scrolling: touch; scrollbar-width: none;
    margin-bottom: 1rem; padding-bottom: 0.25rem;
  }
  .picker-pets::-webkit-scrollbar { display: none; }
  .picker-pet {
    display: flex; flex-direction: column; align-items: center; gap: 0.5rem;
    cursor: pointer; -webkit-tap-highlight-color: transparent;
    flex-shrink: 0; width: 5rem;
  }
  .picker-pet:active { opacity: 0.7; }
  .picker-avatar {
    width: 4rem; height: 4rem; border-radius: 50%;
    background: var(--color-card); border: 2px solid var(--color-border);
    overflow: hidden; display: flex; align-items: center; justify-content: center;
    flex-shrink: 0;
  }
  .picker-avatar img { width: 100%; height: 100%; object-fit: cover; }
  .picker-icon { width: 1.75rem; height: 1.75rem; color: var(--color-muted); }
  .picker-icon :global(svg) { width: 100%; height: 100%; }
  .picker-pet-name { font-size: 0.875rem; font-weight: 500; color: var(--color-text); text-align: center; }
  .picker-pet-sub { font-size: 0.6875rem; color: var(--color-muted); text-align: center; line-height: 1.3; }
  .picker-add-btn {
    display: flex; align-items: center; justify-content: center; gap: 0.5rem;
    width: 100%; padding: 0.75rem;
    background: var(--color-card); border: 1.5px dashed var(--color-border);
    border-radius: 1rem; cursor: pointer; font-family: inherit;
    font-size: 0.9375rem; color: var(--color-muted);
    -webkit-tap-highlight-color: transparent; transition: border-color 0.15s;
  }
  .picker-add-btn:active { opacity: 0.7; }

  .pet-header-actions { display: flex; align-items: center; gap: 0.25rem; }
</style>
