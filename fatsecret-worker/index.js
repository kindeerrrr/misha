/**
 * Cloudflare Worker — FatSecret API proxy
 *
 * Деплой:
 *   1. CF Dashboard → Workers → Create Worker → вставить этот код
 *   2. Settings → Variables → добавить:
 *        FATSECRET_CLIENT_ID     = 165992c341764d85b2650a9bade556ce
 *        FATSECRET_CLIENT_SECRET = a0a936c50e7e4c93b26f8efdcfbee2f9
 *   3. Скопировать URL воркера (вида https://xxx.workers.dev)
 *   4. В Cloudflare Pages → Settings → Environment variables добавить:
 *        VITE_FATSECRET_WORKER_URL = https://xxx.workers.dev
 *
 * Endpoints:
 *   GET /search?q=гречка           → foods.search
 *   GET /barcode?code=4607002941  → food.find_id_for_barcode + food.get.v4
 */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

// ── Token cache (per Worker instance lifetime) ────────────────────────────
let cachedToken = null
let tokenExpiry  = 0

async function getToken(env) {
  if (cachedToken && Date.now() < tokenExpiry) return cachedToken

  const creds = btoa(`${env.FATSECRET_CLIENT_ID}:${env.FATSECRET_CLIENT_SECRET}`)
  const res = await fetch('https://oauth.fatsecret.com/connect/token', {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${creds}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials&scope=basic',
  })

  if (!res.ok) throw new Error(`Token request failed: ${res.status}`)
  const data = await res.json()

  cachedToken  = data.access_token
  tokenExpiry  = Date.now() + (data.expires_in - 300) * 1000
  return cachedToken
}

// ── FatSecret helpers ─────────────────────────────────────────────────────
async function fsGet(token, params) {
  const url = 'https://platform.fatsecret.com/rest/server.api?' +
    new URLSearchParams({ ...params, format: 'json' }).toString()
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  })
  return res.json()
}

// Normalise a single FatSecret serving to per-100g values.
// Returns null if no usable macros found.
function normaliseServing(serving) {
  if (!serving) return null

  const amount = parseFloat(serving.metric_serving_amount ?? '100')
  const factor = amount > 0 ? 100 / amount : 1

  const cal  = parseFloat(serving.calories       ?? '0') * factor
  const prot = parseFloat(serving.protein        ?? '0') * factor
  const fat  = parseFloat(serving.fat            ?? '0') * factor
  const carb = parseFloat(serving.carbohydrate   ?? '0') * factor

  return {
    calories_per_100g: Math.round(cal),
    protein_per_100g:  Math.round(prot  * 10) / 10,
    fat_per_100g:      Math.round(fat   * 10) / 10,
    carbs_per_100g:    Math.round(carb  * 10) / 10,
  }
}

function pickBestServing(servings) {
  if (!servings) return null
  const list = Array.isArray(servings.serving)
    ? servings.serving
    : [servings.serving]

  // Prefer the "100 g" serving if present
  const per100 = list.find(s =>
    (s.serving_description ?? '').toLowerCase().includes('100 g') ||
    parseFloat(s.metric_serving_amount ?? '0') === 100
  )
  return per100 ?? list[0] ?? null
}

// ── Route: /search ────────────────────────────────────────────────────────
async function handleSearch(token, q) {
  const data = await fsGet(token, {
    method: 'foods.search',
    search_expression: q,
    max_results: '10',
  })

  const raw = data?.foods?.food ?? []
  const foods = Array.isArray(raw) ? raw : [raw]

  const results = foods.map(f => {
    const serving = pickBestServing(f.servings)
    const macros  = normaliseServing(serving)
    return {
      id:   f.food_id,
      name: f.food_name,
      type: f.food_type,   // "Generic" | "Brand"
      brand: f.brand_name ?? null,
      ...macros,
    }
  }).filter(f => f.name)

  return json({ results })
}

// ── Route: /barcode ───────────────────────────────────────────────────────
async function handleBarcode(token, code) {
  // Step 1: find food_id from barcode
  const idData = await fsGet(token, {
    method: 'food.find_id_for_barcode',
    barcode: code,
  })

  const foodId = idData?.food_id?.value
  if (!foodId) return json({ found: false })

  // Step 2: get full food data
  const foodData = await fsGet(token, {
    method: 'food.get.v4',
    food_id: foodId,
  })

  const food = foodData?.food
  if (!food) return json({ found: false })

  const serving = pickBestServing(food.servings)
  const macros  = normaliseServing(serving)

  return json({
    found: true,
    id:    food.food_id,
    name:  food.food_name,
    brand: food.brand_name ?? null,
    ...macros,
  })
}

// ── Main fetch handler ────────────────────────────────────────────────────
export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS })
    }

    const url = new URL(request.url)

    try {
      const token = await getToken(env)

      if (url.pathname === '/search') {
        const q = url.searchParams.get('q')?.trim()
        if (!q) return json({ error: 'Missing q' }, 400)
        return handleSearch(token, q)
      }

      if (url.pathname === '/barcode') {
        const code = url.searchParams.get('code')?.trim()
        if (!code) return json({ error: 'Missing code' }, 400)
        return handleBarcode(token, code)
      }

      return new Response('Not found', { status: 404, headers: CORS })
    } catch (err) {
      return json({ error: err.message }, 500)
    }
  },
}
