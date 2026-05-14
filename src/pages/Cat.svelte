<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase } from '../lib/supabase'
  import { user } from '../stores/user'
  import Modal from '../components/ui/Modal.svelte'
  import type { CatProfile, CatVaccine, CatHealthEvent, CatGrooming, CatFoodOrder } from '../lib/types'

  type CatTab = 'profile' | 'vaccines' | 'health' | 'grooming' | 'food'

  let activeTab: CatTab = 'profile'
  let loading = true

  let profile: CatProfile | null = null
  let vaccines: CatVaccine[] = []
  let healthEvents: CatHealthEvent[] = []
  let groomings: CatGrooming[] = []
  let foodOrders: CatFoodOrder[] = []

  // Profile form
  let pName = ''; let pBreed = ''; let pBirth = ''; let pWeight = ''; let pNotes = ''
  let savingProfile = false

  // Vaccine form
  let showVaccModal = false
  let vName = ''; let vDate = ''; let vNextDue = ''; let vClinic = ''; let vNotes = ''
  let savingVacc = false

  // Health form
  let showHealthModal = false
  let hDate = ''; let hDesc = ''; let hVet = false
  let savingHealth = false

  // Grooming form
  let showGroomModal = false
  let gDate = ''; let gType = 'Грумер'; let gNextDue = ''; let gNotes = ''
  let savingGroom = false

  // Food form
  let showFoodModal = false
  let fDate = ''; let fBrand = ''; let fProduct = ''; let fQty = ''; let fPrice = ''; let fNext = ''
  let savingFood = false

  const GROOM_TYPES = ['Грумер', 'Стрижка когтей', 'Чистка ушей', 'Купание']

  async function load() {
    if (!$user) return
    const uid = $user.id
    const [profRes, vaccRes, healthRes, groomRes, foodRes] = await Promise.all([
      supabase.from('cat_profiles').select('*').eq('user_id', uid).maybeSingle(),
      supabase.from('cat_vaccines').select('*').eq('user_id', uid).order('date', { ascending: false }),
      supabase.from('cat_health_events').select('*').eq('user_id', uid).order('date', { ascending: false }),
      supabase.from('cat_groomings').select('*').eq('user_id', uid).order('date', { ascending: false }),
      supabase.from('cat_food_orders').select('*').eq('user_id', uid).order('date', { ascending: false }),
    ])
    profile = profRes.data
    if (profile) {
      pName = profile.name; pBreed = profile.breed ?? ''
      pBirth = profile.birth_date ?? ''; pWeight = profile.weight_kg?.toString() ?? ''
      pNotes = profile.notes ?? ''
    }
    vaccines = vaccRes.data ?? []
    healthEvents = healthRes.data ?? []
    groomings = groomRes.data ?? []
    foodOrders = foodRes.data ?? []
    loading = false
  }

  async function saveProfile() {
    if (!$user || !pName.trim()) return
    savingProfile = true
    const payload = {
      user_id: $user.id,
      name: pName.trim(),
      breed: pBreed || null,
      birth_date: pBirth || null,
      weight_kg: pWeight ? parseFloat(pWeight) : null,
      notes: pNotes || null,
    }
    if (profile) {
      const { data } = await supabase.from('cat_profiles').update(payload).eq('id', profile.id).select().single()
      if (data) profile = data
    } else {
      const { data } = await supabase.from('cat_profiles').insert(payload).select().single()
      if (data) profile = data
    }
    savingProfile = false
  }

  async function addVaccine() {
    if (!$user || !vName.trim() || !vDate) return
    savingVacc = true
    const { data } = await supabase.from('cat_vaccines').insert({
      user_id: $user.id, name: vName.trim(), date: vDate,
      next_due: vNextDue || null, clinic: vClinic || null, notes: vNotes || null,
    }).select().single()
    if (data) vaccines = [data, ...vaccines]
    showVaccModal = false
    vName = ''; vDate = ''; vNextDue = ''; vClinic = ''; vNotes = ''
    savingVacc = false
  }

  async function addHealthEvent() {
    if (!$user || !hDesc.trim() || !hDate) return
    savingHealth = true
    const { data } = await supabase.from('cat_health_events').insert({
      user_id: $user.id, date: hDate, description: hDesc.trim(), vet_visit: hVet,
    }).select().single()
    if (data) healthEvents = [data, ...healthEvents]
    showHealthModal = false
    hDate = ''; hDesc = ''; hVet = false
    savingHealth = false
  }

  async function addGrooming() {
    if (!$user || !gDate) return
    savingGroom = true
    const { data } = await supabase.from('cat_groomings').insert({
      user_id: $user.id, date: gDate, type: gType,
      next_due: gNextDue || null, notes: gNotes || null,
    }).select().single()
    if (data) groomings = [data, ...groomings]
    showGroomModal = false
    gDate = ''; gType = 'Грумер'; gNextDue = ''; gNotes = ''
    savingGroom = false
  }

  async function addFoodOrder() {
    if (!$user || !fBrand.trim() || !fDate) return
    savingFood = true
    const { data } = await supabase.from('cat_food_orders').insert({
      user_id: $user.id, date: fDate, brand: fBrand.trim(),
      product: fProduct || fBrand.trim(), quantity: fQty || null,
      price: fPrice ? parseFloat(fPrice) : null, next_order: fNext || null,
    }).select().single()
    if (data) foodOrders = [data, ...foodOrders]
    showFoodModal = false
    fDate = ''; fBrand = ''; fProduct = ''; fQty = ''; fPrice = ''; fNext = ''
    savingFood = false
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
  <header class="page-header">
    <h1 class="section-title">{profile?.name ?? 'Кошка'}</h1>
  </header>

  <!-- Sub-tabs -->
  <nav class="cat-tabs">
    {#each (['profile', 'vaccines', 'health', 'grooming', 'food'] as CatTab[]) as tab}
      <button class="cat-tab" class:active={activeTab === tab} on:click={() => activeTab = tab}>
        {{ profile: 'Профиль', vaccines: 'Прививки', health: 'Здоровье', grooming: 'Уход', food: 'Корм' }[tab]}
      </button>
    {/each}
  </nav>

  {#if loading}
    <div class="skeleton mt-4" style="height:10rem" />
  {:else}

    <!-- PROFILE -->
    {#if activeTab === 'profile'}
      <div class="profile-form mt-3">
        <div class="form-field">
          <label class="label" for="p-name">Имя</label>
          <input id="p-name" type="text" bind:value={pName} placeholder="Имя кошки" />
        </div>
        <div class="form-field">
          <label class="label" for="p-breed">Порода</label>
          <input id="p-breed" type="text" bind:value={pBreed} placeholder="Необязательно" />
        </div>
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
        <button class="btn-primary mt-2" on:click={saveProfile} disabled={savingProfile || !pName.trim()}>
          {savingProfile ? 'Сохраняю...' : profile ? 'Обновить' : 'Создать профиль'}
        </button>
      </div>
    {/if}

    <!-- VACCINES -->
    {#if activeTab === 'vaccines'}
      <div class="section-actions mt-3">
        <button class="add-btn" on:click={() => showVaccModal = true}>+ Добавить</button>
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
                <button class="del-btn" on:click={() => deleteRow('cat_vaccines', v.id, 'vaccines')}>×</button>
              </div>
            </div>
          {/each}
        </div>
      {/if}
    {/if}

    <!-- HEALTH -->
    {#if activeTab === 'health'}
      <div class="section-actions mt-3">
        <button class="add-btn" on:click={() => showHealthModal = true}>+ Добавить</button>
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
                <button class="del-btn" on:click={() => deleteRow('cat_health_events', e.id, 'health')}>×</button>
              </div>
            </div>
          {/each}
        </div>
      {/if}
    {/if}

    <!-- GROOMING -->
    {#if activeTab === 'grooming'}
      <div class="section-actions mt-3">
        <button class="add-btn" on:click={() => showGroomModal = true}>+ Добавить</button>
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
                </div>
                <button class="del-btn" on:click={() => deleteRow('cat_groomings', g.id, 'groomings')}>×</button>
              </div>
            </div>
          {/each}
        </div>
      {/if}
    {/if}

    <!-- FOOD -->
    {#if activeTab === 'food'}
      <div class="section-actions mt-3">
        <button class="add-btn" on:click={() => showFoodModal = true}>+ Добавить заказ</button>
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
                <button class="del-btn" on:click={() => deleteRow('cat_food_orders', f.id, 'food')}>×</button>
              </div>
            </div>
          {/each}
        </div>
      {/if}
    {/if}

  {/if}
</div>

<!-- Vaccine modal -->
<Modal title="Прививка" open={showVaccModal} on:close={() => showVaccModal = false}>
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
    <button class="btn-primary" on:click={addVaccine} disabled={savingVacc || !vName.trim() || !vDate}>
      {savingVacc ? 'Сохраняю...' : 'Добавить'}
    </button>
  </div>
</Modal>

<!-- Health modal -->
<Modal title="Событие здоровья" open={showHealthModal} on:close={() => showHealthModal = false}>
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
    <button class="btn-primary" on:click={addHealthEvent} disabled={savingHealth || !hDesc.trim() || !hDate}>
      {savingHealth ? 'Сохраняю...' : 'Добавить'}
    </button>
  </div>
</Modal>

<!-- Grooming modal -->
<Modal title="Уход" open={showGroomModal} on:close={() => showGroomModal = false}>
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
    <button class="btn-primary" on:click={addGrooming} disabled={savingGroom || !gDate}>
      {savingGroom ? 'Сохраняю...' : 'Добавить'}
    </button>
  </div>
</Modal>

<!-- Food modal -->
<Modal title="Заказ корма" open={showFoodModal} on:close={() => showFoodModal = false}>
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
    <button class="btn-primary" on:click={addFoodOrder} disabled={savingFood || !fBrand.trim() || !fDate}>
      {savingFood ? 'Сохраняю...' : 'Добавить'}
    </button>
  </div>
</Modal>

<style>
  .page-shell { max-width: 480px; margin: 0 auto; padding: 0 1rem 6rem; }

  .page-header { padding: 1rem 0 0.75rem; }

  .cat-tabs {
    display: flex; overflow-x: auto; gap: 0.375rem;
    scrollbar-width: none; -webkit-overflow-scrolling: touch;
    padding-bottom: 0.25rem;
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

  .section-actions { display: flex; justify-content: flex-end; }
  .add-btn {
    background: var(--color-accent); color: white; border: none;
    border-radius: 0.875rem; padding: 0.5rem 1rem; font-size: 0.875rem; cursor: pointer;
  }

  .profile-form { display: flex; flex-direction: column; gap: 1rem; }

  .item-list { display: flex; flex-direction: column; gap: 0.5rem; }
  .item-card { background: var(--color-card); border: 1px solid var(--color-border); border-radius: 1rem; padding: 0.875rem 1rem; }
  .item-row { display: flex; align-items: flex-start; gap: 0.5rem; }
  .item-main { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .item-title { font-size: 0.9375rem; }
  .item-date { font-size: 0.8125rem; color: var(--color-muted); }
  .item-next { font-size: 0.8125rem; color: var(--color-accent); }
  .item-sub { font-size: 0.75rem; color: var(--color-muted); }
  .del-btn { background: none; border: none; color: var(--color-muted); font-size: 1.25rem; cursor: pointer; padding: 0 0.25rem; line-height: 1; }

  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; flex: 1; }
  .form-row { display: flex; gap: 0.75rem; }

  .radio-group { display: flex; flex-wrap: wrap; gap: 0.375rem; }
  .radio-pill { padding: 0.375rem 0.875rem; border: 1px solid var(--color-border); border-radius: 2rem; font-size: 0.8125rem; cursor: pointer; -webkit-tap-highlight-color: transparent; transition: all 0.15s; }
  .radio-pill.selected { background: var(--color-accent); border-color: var(--color-accent); color: white; }
  .radio-pill input { display: none; }

  .checkbox-row { display: flex; align-items: center; gap: 0.625rem; font-size: 0.9375rem; cursor: pointer; }
  .checkbox-row input { width: 1.125rem; height: 1.125rem; accent-color: var(--color-accent); }

  .empty-state { padding: 2rem; text-align: center; color: var(--color-muted); background: var(--color-card); border-radius: 1.25rem; border: 1px dashed var(--color-border); }

  .skeleton { border-radius: 1.25rem; background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .mt-2 { margin-top: 0.5rem; }
  .mt-3 { margin-top: 0.75rem; }
  .mt-4 { margin-top: 1rem; }
</style>
