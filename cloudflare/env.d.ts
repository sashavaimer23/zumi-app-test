// Типы для локальной проверки (на Cloudflare они встроены)
type PagesFunction = (ctx: { request: Request; params: Record<string, string | string[]>; env: unknown }) =>
  Response | Promise<Response>;
