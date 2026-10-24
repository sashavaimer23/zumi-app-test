// Zumi — ежедневная уборка (Supabase Edge Function).
// Удаляет из хранилища verification-docs фото документов, селфи и фото с проверки на месте:
//   • сразу после решения модератора (если кабинет не успел удалить сам);
//   • любые файлы старше 30 дней (заявка без решения);
//   • «потерянные» файлы, которые не относятся ни к одной заявке.
// Плюс чистит метки показов рекламы (IP и метки устройств хранятся не дольше 2 дней).
//
// Запуск: Supabase → Edge Functions → Deploy new function → имя purge-verification-docs → вставить этот код.
// Расписание: Supabase → Integrations → Cron → New job → каждый день → Supabase Edge Function → purge-verification-docs.
// Ключ service_role берётся из окружения функции автоматически — никуда его вписывать не нужно.
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async () => {
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  let deleted = 0;
  for (let round = 0; round < 20; round++) {
    const { data: names, error } = await db.rpc("docs_purge_list");
    if (error) return new Response(error.message, { status: 500 });
    if (!names || names.length === 0) break;
    const { error: removeError } = await db.storage.from("verification-docs").remove(names as string[]);
    if (removeError) return new Response(removeError.message, { status: 500 });
    const { error: doneError } = await db.rpc("docs_purge_done", { names });
    if (doneError) return new Response(doneError.message, { status: 500 });
    deleted += (names as string[]).length;
  }
  const { error: cleanError } = await db.rpc("cleanup_daily");
  if (cleanError) return new Response(cleanError.message, { status: 500 });
  return Response.json({ deleted });
});
