import { writable } from 'svelte/store'
import type { NavTab, HealthTab } from '../lib/types'

export const activeTab = writable<NavTab>('dashboard')
export const activeHealthTab = writable<HealthTab>('pills')

export const navHistory = writable<NavTab[]>(['dashboard'])

export function navigate(tab: NavTab) {
  activeTab.set(tab)
  navHistory.update(h => [...h, tab])
}
