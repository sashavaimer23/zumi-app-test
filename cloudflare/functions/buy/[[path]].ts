import { areaPage } from "../../lib/areas";
export const onRequestGet: PagesFunction = ({ params }) =>
  areaPage("sale", ([] as string[]).concat((params.path as string[] | string | undefined) ?? []).filter(Boolean));
