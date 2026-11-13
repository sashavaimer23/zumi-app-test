// Типы для локальной проверки (на Cloudflare они встроены)
type PagesFunction = (ctx: {
  request: Request; params: Record<string, string | string[]>; env: unknown;
  next: () => Promise<Response>; waitUntil: (p: Promise<unknown>) => void;
}) => Response | Promise<Response>;
