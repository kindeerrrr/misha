import { writable } from 'svelte/store'
import type { Theme } from '../lib/types'

const STORAGE_KEY = 'misha_theme'

function createThemeStore() {
  const saved = (localStorage.getItem(STORAGE_KEY) as Theme) ?? 'light'
  const { subscribe, set } = writable<Theme>(saved)

  function apply(theme: Theme) {
    document.documentElement.setAttribute('data-theme', theme)
    localStorage.setItem(STORAGE_KEY, theme)
    set(theme)
  }

  apply(saved)

  return {
    subscribe,
    set: apply,
  }
}

export const theme = createThemeStore()
