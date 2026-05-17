import { writable, get } from 'svelte/store'
import { supabase } from '../lib/supabase'
import type { Profile } from '../lib/types'

export const profile = writable<Profile | null>(null)

export async function loadProfile(userId: string) {
  const { data } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .single()
  if (data) profile.set(data)
}

export async function updateProfile(updates: { display_name?: string; username?: string }) {
  const current = get(profile)
  if (!current) return { error: new Error('No profile') }
  const { data, error } = await supabase
    .from('profiles')
    .update(updates)
    .eq('id', current.id)
    .select()
    .single()
  if (data) profile.set(data)
  return { error }
}

export function getFirstName(p: Profile | null): string {
  if (!p) return ''
  if (p.display_name) return p.display_name.split(' ')[0]
  return p.email.split('@')[0]
}
