// Cloudflare Worker — прокси для Supabase (обход блокировки в России)
// Деплой: Cloudflare Dashboard → Workers → Create Worker → вставить этот код

const SUPABASE_HOST = 'zulgtsgddacuoduxqsjl.supabase.co'

export default {
  async fetch(request) {
    const url = new URL(request.url)
    url.hostname = SUPABASE_HOST
    url.port = '443'
    url.protocol = 'https:'

    const headers = new Headers(request.headers)
    headers.set('host', SUPABASE_HOST)

    // CORS для запросов из браузера
    const origin = request.headers.get('origin') ?? '*'

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
          'Access-Control-Allow-Headers': request.headers.get('Access-Control-Request-Headers') ?? '*',
          'Access-Control-Max-Age': '86400',
        },
      })
    }

    const proxied = await fetch(url.toString(), {
      method: request.method,
      headers,
      body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
    })

    const resp = new Response(proxied.body, proxied)
    resp.headers.set('Access-Control-Allow-Origin', origin)
    resp.headers.set('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS')
    return resp
  },
}
