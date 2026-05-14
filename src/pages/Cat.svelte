<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase } from '../lib/supabase'
  import { user } from '../stores/user'
  import Modal from '../components/ui/Modal.svelte'
  import type { CatProfile, CatVaccine, CatHealthEvent, CatGrooming, CatFoodOrder } from '../lib/types'

  type CatTab = 'profile' | 'vaccines' | 'health' | 'grooming' | 'food'
  type View = 'list' | 'pet'

  const CAT_TABS: CatTab[] = ['profile', 'vaccines', 'health', 'grooming', 'food']
  const CAT_TAB_LABELS: Record<CatTab, string> = {
    profile: 'Профиль', vaccines: 'Прививки', health: 'Здоровье', grooming: 'Уход', food: 'Корм'
  }
  const GROOM_TYPES = ['Грумер', 'Стрижка когтей', 'Чистка ушей', 'Купание']

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

  function breedsFor(type: string) {
    if (type === 'dog') return DOG_BREEDS
    if (type === 'cat') return CAT_BREEDS
    return []
  }
  function colorsFor(type: string) {
    if (type === 'dog') return DOG_COLORS
    if (type === 'cat') return CAT_COLORS
    return []
  }

  const ANIMAL_TYPES = [
    { id: 'cat',     label: 'Кошка',   emoji: '🐱' },
    { id: 'dog',     label: 'Собака',  emoji: '🐶' },
    { id: 'hamster', label: 'Хомяк',   emoji: '🐹' },
    { id: 'bird',    label: 'Птица',   emoji: '🐦' },
    { id: 'other',   label: 'Другое',  emoji: '🐾' },
  ]

  let view: View = 'list'
  let activeTab: CatTab = 'profile'
  let loading = true

  let profiles: CatProfile[] = []
  let selectedProfile: CatProfile | null = null
  let isNewPet = false

  let vaccines: CatVaccine[] = []
  let healthEvents: CatHealthEvent[] = []
  let groomings: CatGrooming[] = []
  let foodOrders: CatFoodOrder[] = []

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
  let hDate = ''; let hDesc = ''; let hVet = false
  let savingHealth = false

  // Grooming form
  let showGroomModal = false; let editingGroom: CatGrooming | null = null
  let gDate = ''; let gType = 'Грумер'; let gNextDue = ''; let gNotes = ''
  let savingGroom = false

  // Food form
  let showFoodModal = false; let editingFood: CatFoodOrder | null = null
  let fDate = ''; let fBrand = ''; let fProduct = ''; let fQty = ''; let fPrice = ''; let fNext = ''
  let savingFood = false

  function petEmoji(type: string | null | undefined) {
    return ANIMAL_TYPES.find(t => t.id === type)?.emoji ?? '🐾'
  }

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

  async function load() {
    if (!$user) return
    const res = await supabase.from('cat_profiles').select('*').eq('user_id', $user.id).order('created_at')
    profiles = res.data ?? []
    if (profiles.length === 1) {
      await openPet(profiles[0])
    }
    loading = false
  }

  function fillForm(p: CatProfile) {
    pName = p.name; pBreed = p.breed ?? ''; pBirth = p.birth_date ?? ''
    pWeight = p.weight_kg?.toString() ?? ''; pNotes = p.notes ?? ''
    pAnimalType = p.animal_type ?? 'cat'; pPhotoUrl = p.photo_url ?? ''
    pCoatColor = p.coat_color ?? ''
    isNewPet = false; saveError = ''
  }

  async function openPet(p: CatProfile) {
    selectedProfile = p
    fillForm(p)
    activeTab = 'profile'
    await loadPetData(p.id)
    view = 'pet'
  }

  function startNewPet() {
    selectedProfile = null
    pName = ''; pBreed = ''; pBirth = ''; pWeight = ''; pNotes = ''
    pAnimalType = 'cat'; pPhotoUrl = ''; pCoatColor = ''
    saveError = ''; isNewPet = true
    vaccines = []; healthEvents = []; groomings = []; foodOrders = []
    activeTab = 'profile'
    view = 'pet'
  }

  function goBack() {
    view = 'list'
    selectedProfile = null
    isNewPet = false
  }

  async function loadPetData(catId: string) {
    const [vaccRes, healthRes, groomRes, foodRes] = await Promise.all([
      supabase.from('cat_vaccines').select('*').eq('cat_id', catId).order('date', { ascending: false }),
      supabase.from('cat_health_events').select('*').eq('cat_id', catId).order('date', { ascending: false }),
      supabase.from('cat_groomings').select('*').eq('cat_id', catId).order('date', { ascending: false }),
      supabase.from('cat_food_orders').select('*').eq('cat_id', catId).order('date', { ascending: false }),
    ])
    vaccines = vaccRes.data ?? []
    healthEvents = healthRes.data ?? []
    groomings = groomRes.data ?? []
    foodOrders = foodRes.data ?? []
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
    const payload = {
      user_id: $user.id,
      name: pName.trim(),
      breed: pBreed || null,
      birth_date: pBirth || null,
      weight_kg: pWeight ? parseFloat(pWeight) : null,
      notes: pNotes || null,
      animal_type: pAnimalType,
      photo_url: pPhotoUrl || null,
      coat_color: pCoatColor || null,
    }
    if (selectedProfile) {
      const { data, error } = await supabase.from('cat_profiles').update(payload).eq('id', selectedProfile.id).select().single()
      if (error) { saveError = error.message }
      else if (data) { selectedProfile = data; profiles = profiles.map(p => p.id === data.id ? data : p) }
    } else {
      const { data, error } = await supabase.from('cat_profiles').insert(payload).select().single()
      if (error) { saveError = error.message }
      else if (data) { profiles = [...profiles, data]; selectedProfile = data; isNewPet = false }
    }
    savingProfile = false
  }

  async function deletePet() {
    if (!selectedProfile) return
    await supabase.from('cat_profiles').delete().eq('id', selectedProfile.id)
    profiles = profiles.filter(p => p.id !== selectedProfile!.id)
    goBack()
  }

  // Vaccine
  function openVacc(v?: CatVaccine) {
    editingVacc = v ?? null
    vName = v?.name ?? ''; vDate = v?.date ?? ''
    vNextDue = v?.next_due ?? ''; vClinic = v?.clinic ?? ''; vNotes = v?.notes ?? ''
    showVaccModal = true
  }

  async function saveVaccine() {
    if (!$user || !selectedProfile || !vName.trim() || !vDate) return
    savingVacc = true
    const payload = { user_id: $user.id, cat_id: selectedProfile.id, name: vName.trim(), date: vDate, next_due: vNextDue || null, clinic: vClinic || null, notes: vNotes || null }
    if (editingVacc) {
      const { data } = await supabase.from('cat_vaccines').update(payload).eq('id', editingVacc.id).select().single()
      if (data) vaccines = vaccines.map(v => v.id === editingVacc!.id ? data : v)
    } else {
      const { data } = await supabase.from('cat_vaccines').insert(payload).select().single()
      if (data) vaccines = [data, ...vaccines]
    }
    showVaccModal = false; savingVacc = false
  }

  // Health
  function openHealth(e?: CatHealthEvent) {
    editingHealth = e ?? null
    hDate = e?.date ?? ''; hDesc = e?.description ?? ''; hVet = e?.vet_visit ?? false
    showHealthModal = true
  }

  async function saveHealthEvent() {
    if (!$user || !selectedProfile || !hDesc.trim() || !hDate) return
    savingHealth = true
    const payload = { user_id: $user.id, cat_id: selectedProfile.id, date: hDate, description: hDesc.trim(), vet_visit: hVet }
    if (editingHealth) {
      const { data } = await supabase.from('cat_health_events').update(payload).eq('id', editingHealth.id).select().single()
      if (data) healthEvents = healthEvents.map(e => e.id === editingHealth!.id ? data : e)
    } else {
      const { data } = await supabase.from('cat_health_events').insert(payload).select().single()
      if (data) healthEvents = [data, ...healthEvents]
    }
    showHealthModal = false; savingHealth = false
  }

  // Grooming
  function openGroom(g?: CatGrooming) {
    editingGroom = g ?? null
    gDate = g?.date ?? ''; gType = g?.type ?? 'Грумер'
    gNextDue = g?.next_due ?? ''; gNotes = g?.notes ?? ''
    showGroomModal = true
  }

  async function saveGrooming() {
    if (!$user || !selectedProfile || !gDate) return
    savingGroom = true
    const payload = { user_id: $user.id, cat_id: selectedProfile.id, date: gDate, type: gType, next_due: gNextDue || null, notes: gNotes || null }
    if (editingGroom) {
      const { data } = await supabase.from('cat_groomings').update(payload).eq('id', editingGroom.id).select().single()
      if (data) groomings = groomings.map(g => g.id === editingGroom!.id ? data : g)
    } else {
      const { data } = await supabase.from('cat_groomings').insert(payload).select().single()
      if (data) groomings = [data, ...groomings]
    }
    showGroomModal = false; savingGroom = false
  }

  // Food
  function openFood(f?: CatFoodOrder) {
    editingFood = f ?? null
    fDate = f?.date ?? ''; fBrand = f?.brand ?? ''; fProduct = f?.product ?? ''
    fQty = f?.quantity ?? ''; fPrice = f?.price?.toString() ?? ''; fNext = f?.next_order ?? ''
    showFoodModal = true
  }

  async function saveFoodOrder() {
    if (!$user || !selectedProfile || !fBrand.trim() || !fDate) return
    savingFood = true
    const payload = { user_id: $user.id, cat_id: selectedProfile.id, date: fDate, brand: fBrand.trim(), product: fProduct || fBrand.trim(), quantity: fQty || null, price: fPrice ? parseFloat(fPrice) : null, next_order: fNext || null }
    if (editingFood) {
      const { data } = await supabase.from('cat_food_orders').update(payload).eq('id', editingFood.id).select().single()
      if (data) foodOrders = foodOrders.map(f => f.id === editingFood!.id ? data : f)
    } else {
      const { data } = await supabase.from('cat_food_orders').insert(payload).select().single()
      if (data) foodOrders = [data, ...foodOrders]
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

  function fmt(d: string) {
    return new Date(d + 'T12:00:00').toLocaleDateString('ru', { day: 'numeric', month: 'short', year: 'numeric' })
  }

  onMount(load)
</script>

<div class="page-shell">
  {#if loading}
    <div class="skeleton mt-4" style="height:10rem" />

  {:else if view === 'list'}
    <!-- LANDING -->
    <header class="page-header">
      <h1 class="section-title">Животные</h1>
      <button class="add-btn" on:click={startNewPet}>+ Добавить</button>
    </header>

    {#if profiles.length === 0}
      <div class="empty-state mt-4">
        <div class="empty-emoji">🐾</div>
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
                <span class="pet-emoji-big">{petEmoji(p.animal_type)}</span>
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

  {:else}
    <!-- PET PROFILE -->
    <header class="page-header">
      <button class="back-btn" on:click={goBack}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75"><path d="M19 12H5M12 5l-7 7 7 7"/></svg>
      </button>
      <h1 class="section-title pet-header-name">{isNewPet ? 'Новый питомец' : (selectedProfile?.name ?? '')}</h1>
      {#if selectedProfile}
        <span class="pet-type-badge">{petEmoji(selectedProfile.animal_type)}</span>
      {/if}
    </header>

    <nav class="cat-tabs">
      {#each CAT_TABS as tab}
        <button class="cat-tab" class:active={activeTab === tab} on:click={() => activeTab = tab}>
          {CAT_TAB_LABELS[tab]}
        </button>
      {/each}
    </nav>

    <!-- PROFILE TAB -->
    {#if activeTab === 'profile'}
      <div class="profile-form mt-3">

        <!-- Photo -->
        <div class="photo-field">
          <div class="photo-preview-wrap">
            {#if pPhotoUrl}
              <img src={pPhotoUrl} alt="Фото питомца" class="photo-preview" />
            {:else}
              <div class="photo-placeholder">{petEmoji(pAnimalType)}</div>
            {/if}
          </div>
          <label class="photo-upload-btn">
            {uploadingPhoto ? 'Загружаю...' : 'Загрузить фото'}
            <input type="file" accept="image/*" on:change={handlePhotoChange} style="display:none" disabled={uploadingPhoto} />
          </label>
        </div>

        <!-- Animal type -->
        <div class="form-field">
          <label class="label">Тип животного</label>
          <div class="animal-type-row">
            {#each ANIMAL_TYPES as t}
              <button
                class="animal-type-btn"
                class:selected={pAnimalType === t.id}
                on:click={() => pAnimalType = t.id}
              >
                <span class="animal-emoji">{t.emoji}</span>
                <span class="animal-label">{t.label}</span>
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
                <button
                  class="chip"
                  class:selected={pBreed === b}
                  on:click={() => pBreed = pBreed === b ? '' : b}
                >{b}</button>
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
                <button
                  class="chip"
                  class:selected={pCoatColor === c}
                  on:click={() => pCoatColor = pCoatColor === c ? '' : c}
                >{c}</button>
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
          <textarea id="p-notes" bind:value={pNotes} rows="3" placeholder="Особенности, диета..." />
        </div>
        {#if saveError}
          <p class="save-error">{saveError}</p>
        {/if}
        <button class="btn-primary mt-2" on:click={saveProfile} disabled={savingProfile || !pName.trim()}>
          {savingProfile ? 'Сохраняю...' : selectedProfile ? 'Обновить' : 'Создать профиль'}
        </button>
        {#if selectedProfile}
          <button class="btn-ghost" style="margin-top:-0.5rem;color:var(--color-danger,#ef4444)" on:click={deletePet}>
            Удалить питомца
          </button>
        {/if}
      </div>
    {/if}

    {#if selectedProfile}
      <!-- VACCINES -->
      {#if activeTab === 'vaccines'}
        <div class="section-actions mt-3">
          <button class="add-btn" on:click={() => openVacc()}>+ Добавить</button>
        </div>
        {#if vaccines.length === 0}
          <div class="empty-state mt-3">Прививок пока нет</div>
        {:else}
          <div class="item-list mt-3">
            {#each vaccines as v}
              <div class="item-card">
                <div class="item-row">
                  <div class="item-main">
                    <span class="item-title">{v.name}</span>
                    <span class="item-date">{fmt(v.date)}</span>
                    {#if v.next_due}<span class="item-next">Следующая: {fmt(v.next_due)}</span>{/if}
                    {#if v.clinic}<span class="item-sub">{v.clinic}</span>{/if}
                  </div>
                  <div class="item-btns">
                    <button class="edit-btn" on:click={() => openVacc(v)}>Изм.</button>
                    <button class="del-btn" on:click={() => deleteRow('cat_vaccines', v.id, 'vaccines')}>×</button>
                  </div>
                </div>
              </div>
            {/each}
          </div>
        {/if}
      {/if}

      <!-- HEALTH -->
      {#if activeTab === 'health'}
        <div class="section-actions mt-3">
          <button class="add-btn" on:click={() => openHealth()}>+ Добавить</button>
        </div>
        {#if healthEvents.length === 0}
          <div class="empty-state mt-3">Событий здоровья нет</div>
        {:else}
          <div class="item-list mt-3">
            {#each healthEvents as e}
              <div class="item-card">
                <div class="item-row">
                  <div class="item-main">
                    <span class="item-date">{fmt(e.date)}{e.vet_visit ? ' · Визит к ветеринару' : ''}</span>
                    <span class="item-title">{e.description}</span>
                  </div>
                  <div class="item-btns">
                    <button class="edit-btn" on:click={() => openHealth(e)}>Изм.</button>
                    <button class="del-btn" on:click={() => deleteRow('cat_health_events', e.id, 'health')}>×</button>
                  </div>
                </div>
              </div>
            {/each}
          </div>
        {/if}
      {/if}

      <!-- GROOMING -->
      {#if activeTab === 'grooming'}
        <div class="section-actions mt-3">
          <button class="add-btn" on:click={() => openGroom()}>+ Добавить</button>
        </div>
        {#if groomings.length === 0}
          <div class="empty-state mt-3">Визитов к грумеру нет</div>
        {:else}
          <div class="item-list mt-3">
            {#each groomings as g}
              <div class="item-card">
                <div class="item-row">
                  <div class="item-main">
                    <span class="item-title">{g.type}</span>
                    <span class="item-date">{fmt(g.date)}</span>
                    {#if g.next_due}<span class="item-next">Следующий: {fmt(g.next_due)}</span>{/if}
                    {#if g.notes}<span class="item-sub">{g.notes}</span>{/if}
                  </div>
                  <div class="item-btns">
                    <button class="edit-btn" on:click={() => openGroom(g)}>Изм.</button>
                    <button class="del-btn" on:click={() => deleteRow('cat_groomings', g.id, 'groomings')}>×</button>
                  </div>
                </div>
              </div>
            {/each}
          </div>
        {/if}
      {/if}

      <!-- FOOD -->
      {#if activeTab === 'food'}
        <div class="section-actions mt-3">
          <button class="add-btn" on:click={() => openFood()}>+ Добавить заказ</button>
        </div>
        {#if foodOrders.length === 0}
          <div class="empty-state mt-3">Заказов корма нет</div>
        {:else}
          <div class="item-list mt-3">
            {#each foodOrders as f}
              <div class="item-card">
                <div class="item-row">
                  <div class="item-main">
                    <span class="item-title">{f.brand} — {f.product}</span>
                    <span class="item-date">{fmt(f.date)}{f.quantity ? ' · ' + f.quantity : ''}{f.price ? ' · ' + f.price.toLocaleString('ru') + ' ₽' : ''}</span>
                    {#if f.next_order}<span class="item-next">Следующий: {fmt(f.next_order)}</span>{/if}
                  </div>
                  <div class="item-btns">
                    <button class="edit-btn" on:click={() => openFood(f)}>Изм.</button>
                    <button class="del-btn" on:click={() => deleteRow('cat_food_orders', f.id, 'food')}>×</button>
                  </div>
                </div>
              </div>
            {/each}
          </div>
        {/if}
      {/if}
    {/if}
  {/if}
</div>

<!-- Vaccine modal -->
<Modal title={editingVacc ? 'Редактировать прививку' : 'Прививка'} open={showVaccModal} on:close={() => showVaccModal = false}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="v-name">Название</label>
      <input id="v-name" type="text" bind:value={vName} placeholder="Комплексная, Бешенство..." />
    </div>
    <div class="form-field">
      <label class="label" for="v-date">Дата</label>
      <input id="v-date" type="date" bind:value={vDate} />
    </div>
    <div class="form-field">
      <label class="label" for="v-next">Следующая (необязательно)</label>
      <input id="v-next" type="date" bind:value={vNextDue} />
    </div>
    <div class="form-field">
      <label class="label" for="v-clinic">Клиника</label>
      <input id="v-clinic" type="text" bind:value={vClinic} placeholder="Необязательно" />
    </div>
    <button class="btn-primary" on:click={saveVaccine} disabled={savingVacc || !vName.trim() || !vDate}>
      {savingVacc ? 'Сохраняю...' : editingVacc ? 'Обновить' : 'Добавить'}
    </button>
  </div>
</Modal>

<!-- Health modal -->
<Modal title={editingHealth ? 'Редактировать событие' : 'Событие здоровья'} open={showHealthModal} on:close={() => showHealthModal = false}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="h-date">Дата</label>
      <input id="h-date" type="date" bind:value={hDate} />
    </div>
    <div class="form-field">
      <label class="label" for="h-desc">Описание</label>
      <textarea id="h-desc" bind:value={hDesc} rows="3" placeholder="Что случилось? Симптомы, лечение..." />
    </div>
    <label class="checkbox-row">
      <input type="checkbox" bind:checked={hVet} />
      <span>Визит к ветеринару</span>
    </label>
    <button class="btn-primary" on:click={saveHealthEvent} disabled={savingHealth || !hDesc.trim() || !hDate}>
      {savingHealth ? 'Сохраняю...' : editingHealth ? 'Обновить' : 'Добавить'}
    </button>
  </div>
</Modal>

<!-- Grooming modal -->
<Modal title={editingGroom ? 'Редактировать уход' : 'Уход'} open={showGroomModal} on:close={() => showGroomModal = false}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label">Тип</label>
      <div class="radio-group">
        {#each GROOM_TYPES as t}
          <label class="radio-pill" class:selected={gType === t}>
            <input type="radio" bind:group={gType} value={t} />{t}
          </label>
        {/each}
      </div>
    </div>
    <div class="form-field">
      <label class="label" for="g-date">Дата</label>
      <input id="g-date" type="date" bind:value={gDate} />
    </div>
    <div class="form-field">
      <label class="label" for="g-next">Следующий визит</label>
      <input id="g-next" type="date" bind:value={gNextDue} />
    </div>
    <div class="form-field">
      <label class="label" for="g-notes">Заметка</label>
      <input id="g-notes" type="text" bind:value={gNotes} placeholder="Необязательно" />
    </div>
    <button class="btn-primary" on:click={saveGrooming} disabled={savingGroom || !gDate}>
      {savingGroom ? 'Сохраняю...' : editingGroom ? 'Обновить' : 'Добавить'}
    </button>
  </div>
</Modal>

<!-- Food modal -->
<Modal title={editingFood ? 'Редактировать заказ' : 'Заказ корма'} open={showFoodModal} on:close={() => showFoodModal = false}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="f-brand">Бренд</label>
      <input id="f-brand" type="text" bind:value={fBrand} placeholder="Royal Canin, Purina..." />
    </div>
    <div class="form-field">
      <label class="label" for="f-product">Продукт</label>
      <input id="f-product" type="text" bind:value={fProduct} placeholder="Sterilised, Indoor..." />
    </div>
    <div class="form-field">
      <label class="label" for="f-date">Дата заказа</label>
      <input id="f-date" type="date" bind:value={fDate} />
    </div>
    <div class="form-row">
      <div class="form-field">
        <label class="label" for="f-qty">Количество</label>
        <input id="f-qty" type="text" bind:value={fQty} placeholder="2 кг, 6 шт..." />
      </div>
      <div class="form-field">
        <label class="label" for="f-price">Цена ₽</label>
        <input id="f-price" type="number" bind:value={fPrice} placeholder="1200" inputmode="numeric" />
      </div>
    </div>
    <div class="form-field">
      <label class="label" for="f-next">Следующий заказ</label>
      <input id="f-next" type="date" bind:value={fNext} />
    </div>
    <button class="btn-primary" on:click={saveFoodOrder} disabled={savingFood || !fBrand.trim() || !fDate}>
      {savingFood ? 'Сохраняю...' : editingFood ? 'Обновить' : 'Добавить'}
    </button>
  </div>
</Modal>

<style>
  .page-header {
    display: flex; align-items: center; gap: 0.75rem;
    padding: 1rem 0 0.75rem;
  }
  .section-title { flex: 1; }

  .add-btn {
    background: var(--color-accent); color: white; border: none;
    border-radius: 0.875rem; padding: 0.5rem 1rem; font-size: 0.875rem;
    cursor: pointer; flex-shrink: 0; -webkit-tap-highlight-color: transparent;
  }

  .back-btn {
    background: none; border: none; color: var(--color-text);
    cursor: pointer; padding: 0.25rem; display: flex; align-items: center;
    flex-shrink: 0; -webkit-tap-highlight-color: transparent;
  }

  .pet-type-badge { font-size: 1.5rem; flex-shrink: 0; }
  .pet-header-name { font-size: 1.25rem; }

  /* Landing grid */
  .pet-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 0.75rem;
    margin-top: 0.5rem;
  }

  .pet-card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    padding: 1.25rem 1rem 1rem;
    cursor: pointer;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.75rem;
    -webkit-tap-highlight-color: transparent;
    transition: opacity 0.15s;
  }
  .pet-card:active { opacity: 0.75; }

  .pet-avatar {
    width: 5rem; height: 5rem;
    border-radius: 50%;
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    display: flex; align-items: center; justify-content: center;
    overflow: hidden;
    flex-shrink: 0;
  }

  .pet-img { width: 100%; height: 100%; object-fit: cover; }
  .pet-emoji-big { font-size: 2.5rem; line-height: 1; }

  .pet-card-info {
    display: flex; flex-direction: column; align-items: center;
    gap: 2px; text-align: center;
  }
  .pet-card-name { font-size: 1rem; font-weight: 500; color: var(--color-text); }
  .pet-card-sub { font-size: 0.75rem; color: var(--color-muted); }
  .pet-card-age {
    font-size: 0.75rem; color: var(--color-accent);
    font-family: "JetBrains Mono", monospace;
  }

  /* Sub-tabs */
  .cat-tabs {
    display: flex; overflow-x: auto; gap: 0.375rem;
    scrollbar-width: none; -webkit-overflow-scrolling: touch;
    padding-bottom: 0.25rem; margin-bottom: 0.25rem;
  }
  .cat-tabs::-webkit-scrollbar { display: none; }

  .cat-tab {
    flex: 0 0 auto; padding: 0.375rem 0.875rem;
    border: 1px solid var(--color-border); border-radius: 2rem;
    background: var(--color-card); font-size: 0.875rem;
    color: var(--color-muted); cursor: pointer; white-space: nowrap;
    -webkit-tap-highlight-color: transparent; transition: all 0.15s;
  }
  .cat-tab.active { background: var(--color-accent); border-color: var(--color-accent); color: white; }

  /* Photo field */
  .photo-field {
    display: flex; align-items: center; gap: 1rem;
    padding: 0.75rem; background: var(--color-bg);
    border: 1px solid var(--color-border); border-radius: 1rem;
  }

  .photo-preview-wrap {
    width: 4rem; height: 4rem; border-radius: 50%;
    background: var(--color-card); border: 1px solid var(--color-border);
    overflow: hidden; display: flex; align-items: center; justify-content: center;
    flex-shrink: 0;
  }
  .photo-preview { width: 100%; height: 100%; object-fit: cover; }
  .photo-placeholder { font-size: 1.75rem; line-height: 1; }

  .photo-upload-btn {
    flex: 1; padding: 0.5rem 0.875rem;
    border: 1px dashed var(--color-border); border-radius: 0.75rem;
    font-size: 0.875rem; color: var(--color-accent);
    cursor: pointer; text-align: center;
    -webkit-tap-highlight-color: transparent;
  }

  /* Animal type selector */
  .animal-type-row {
    display: flex; gap: 0.375rem; flex-wrap: wrap;
  }

  .animal-type-btn {
    display: flex; flex-direction: column; align-items: center; gap: 2px;
    padding: 0.5rem 0.625rem;
    border: 1px solid var(--color-border); border-radius: 0.875rem;
    background: var(--color-card); cursor: pointer;
    -webkit-tap-highlight-color: transparent; transition: all 0.15s;
  }
  .animal-type-btn.selected {
    border-color: var(--color-accent);
    background: var(--color-accent);
    color: white;
  }
  .animal-emoji { font-size: 1.25rem; line-height: 1; }
  .animal-label { font-size: 0.6875rem; color: var(--color-muted); white-space: nowrap; }
  .animal-type-btn.selected .animal-label { color: rgba(255,255,255,0.85); }

  /* Chip grid for breed/color */
  .chip-grid {
    display: flex; flex-wrap: wrap; gap: 0.375rem;
  }
  .chip {
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--color-border); border-radius: 2rem;
    background: var(--color-card); font-size: 0.8125rem;
    color: var(--color-muted); cursor: pointer;
    -webkit-tap-highlight-color: transparent; transition: all 0.15s;
    white-space: nowrap;
  }
  .chip.selected {
    background: var(--color-accent); border-color: var(--color-accent); color: white;
  }

  .save-error {
    font-size: 0.8125rem; color: #ef4444;
    background: rgba(239,68,68,0.08); border-radius: 0.5rem;
    padding: 0.5rem 0.75rem; margin: 0;
  }

  /* Profile form */
  .profile-form { display: flex; flex-direction: column; gap: 1rem; }

  /* Record lists */
  .section-actions { display: flex; justify-content: flex-end; }
  .item-list { display: flex; flex-direction: column; gap: 0.5rem; }
  .item-card { background: var(--color-card); border: 1px solid var(--color-border); border-radius: 1rem; padding: 0.875rem 1rem; }
  .item-row { display: flex; align-items: flex-start; gap: 0.5rem; }
  .item-main { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .item-title { font-size: 0.9375rem; }
  .item-date { font-size: 0.8125rem; color: var(--color-muted); }
  .item-next { font-size: 0.8125rem; color: var(--color-accent); }
  .item-sub { font-size: 0.75rem; color: var(--color-muted); }

  .item-btns { display: flex; align-items: center; gap: 0.25rem; }
  .edit-btn { background: none; border: none; color: var(--color-accent); font-size: 0.75rem; cursor: pointer; padding: 0.125rem 0.375rem; }
  .del-btn { background: none; border: none; color: var(--color-muted); font-size: 1.25rem; cursor: pointer; padding: 0 0.25rem; line-height: 1; }

  /* Modals */
  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; flex: 1; }
  .form-row { display: flex; gap: 0.75rem; }

  .radio-group { display: flex; flex-wrap: wrap; gap: 0.375rem; }
  .radio-pill { padding: 0.375rem 0.875rem; border: 1px solid var(--color-border); border-radius: 2rem; font-size: 0.8125rem; cursor: pointer; -webkit-tap-highlight-color: transparent; transition: all 0.15s; }
  .radio-pill.selected { background: var(--color-accent); border-color: var(--color-accent); color: white; }
  .radio-pill input { display: none; }

  .checkbox-row { display: flex; align-items: center; gap: 0.625rem; font-size: 0.9375rem; cursor: pointer; }
  .checkbox-row input { width: 1.125rem; height: 1.125rem; accent-color: var(--color-accent); }

  .empty-state {
    padding: 2.5rem 2rem; text-align: center; color: var(--color-muted);
    background: var(--color-card); border-radius: 1.25rem;
    border: 1px dashed var(--color-border);
    display: flex; flex-direction: column; align-items: center; gap: 0.5rem;
  }
  .empty-emoji { font-size: 2.5rem; }

  .skeleton { border-radius: 1.25rem; background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .mt-2 { margin-top: 0.5rem; }
  .mt-3 { margin-top: 0.75rem; }
  .mt-4 { margin-top: 1rem; }
</style>
