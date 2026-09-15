export function environment(name: string): string {
  const value = Deno.env.get(name)
  if (!value) throw new Error(`missing_${name.toLowerCase()}`)
  return value
}

export function serviceHeaders(): HeadersInit {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  const keys = legacy ? {} : JSON.parse(environment("SUPABASE_SECRET_KEYS")) as Record<string, string>
  const key = legacy ?? keys.default ?? Object.values(keys)[0]
  if (!key) throw new Error("missing_supabase_secret_key")
  const headers: Record<string, string> = { apikey: key }
  if (key.split(".").length === 3) headers.Authorization = `Bearer ${key}`
  return headers
}
