<script lang="ts">
  import { createEventDispatcher } from 'svelte'

  export let date: string  // YYYY-MM-DD

  const dispatch = createEventDispatcher<{ change: string }>()
  const todayStr = new Date().toISOString().slice(0, 10)

  function shift(days: number) {
    const d = new Date(date + 'T12:00:00')
    d.setDate(d.getDate() + days)
    const next = d.toISOString().slice(0, 10)
    if (next > todayStr) return
    dispatch('change', next)
  }

  function onInput(e: Event) {
    const val = (e.target as HTMLInputElement).value
    if (val && val <= todayStr) dispatch('change', val)
  }

  function label(d: string): string {
    if (d === todayStr) return 'Сегодня'
    const prev = new Date(); prev.setDate(prev.getDate() - 1)
    if (d === prev.toISOString().slice(0, 10)) return 'Вчера'
    return new Date(d + 'T12:00:00').toLocaleDateString('ru', { day: 'numeric', month: 'long' })
  }
</script>

<div class="date-nav">
  <button class="arrow" on:click={() => shift(-1)}>‹</button>
  <label class="date-label">
    <span>{label(date)}</span>
    <input type="date" value={date} max={todayStr} on:change={onInput} />
  </label>
  <button class="arrow" class:dim={date >= todayStr} on:click={() => shift(1)}>›</button>
</div>

<style>
  .date-nav {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.25rem;
  }

  .arrow {
    width: 2rem;
    height: 2rem;
    background: none;
    border: none;
    font-size: 1.375rem;
    color: var(--color-accent);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 0.5rem;
    -webkit-tap-highlight-color: transparent;
    transition: opacity 0.15s;
    line-height: 1;
  }
  .arrow:active { opacity: 0.5; }
  .arrow.dim { color: var(--color-border); pointer-events: none; }

  .date-label {
    position: relative;
    cursor: pointer;
    padding: 0.25rem 0.625rem;
    border-radius: 0.625rem;
    font-size: 0.9375rem;
    color: var(--color-text);
    font-weight: 500;
    min-width: 7rem;
    text-align: center;
  }
  .date-label:active { opacity: 0.7; }

  input[type="date"] {
    position: absolute;
    inset: 0;
    opacity: 0;
    width: 100%;
    cursor: pointer;
  }
</style>
