import { writable } from 'svelte/store'
import type { NavTab, HealthTab } from '../lib/types'

const NAV_KEY = 'misha_nav_tab'
const HEALTH_KEY = 'misha_health_tab'

const savedTab = (localStorage.getItem(NAV_KEY) as NavTab) ?? 'dashboard'
const savedHealthTab = (localStorage.getItem(HEALTH_KEY) as HealthTab) ?? 'hub'

export const activeTab = writable<NavTab>(savedTab)
export const activeHealthTab = writable<HealthTab>(savedHealthTab)
export const navHistory = writable<NavTab[]>([savedTab])

activeTab.subscribe(tab => localStorage.setItem(NAV_KEY, tab))
activeHealthTab.subscribe(tab => localStorage.setItem(HEALTH_KEY, tab))

export function navigate(tab: NavTab, healthTab?: HealthTab) {
  activeTab.set(tab)
  if (healthTab) activeHealthTab.set(healthTab)
  navHistory.update(h => [...h, tab])
}
