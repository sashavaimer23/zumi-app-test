// /l/<id> — объявление. Лёгкая страница для ВСЕХ (люди, Google, WhatsApp-превью): открывается за 1–2 секунды
// даже на плохом интернете. Полный сайт — по кнопке «See map, save and more homes on Zumi».
import { notFound } from "../../lib/zumi";
import { catalogItem, listingPage } from "../../lib/catalog_item";

export const onRequestGet: PagesFunction = async ({ request, params }) => {
  const id = String(params.id ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(id)) return notFound();
  const c = new URL(request.url).searchParams.get("c");
  if (c) {
    const r = await catalogItem(id, c.toLowerCase());
    if (r) return r;
  }
  return (await listingPage(id)) ?? notFound();
};
