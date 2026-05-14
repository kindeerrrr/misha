import { writable } from 'svelte/store'
import type { User, Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'

export const user = writable<User | null>(null)
export const session = writable<Session | null>(null)
export const authLoading = writable(true)

supabase.auth.getSession().then(({ data }) => {
  session.set(data.session)
  user.set(data.session?.user ?? null)
  authLoading.set(false)
})

supabase.auth.onAuthStateChange((_event, s) => {
  session.set(s)
  user.set(s?.user ?? null)
  authLoading.set(false)
})

export async function signInWithMagicLink(email: string) {
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: {
      emailRedirectTo: `${window.location.origin}/misha/`,
    },
  })
  return { error }
}

export async function signOut() {
  await supabase.auth.signOut()
}
