import { areaPage } from "../../lib/areas";
export const onRequestGet: PagesFunction = ({ params }) =>
  areaPage("rent", ([] as string[]).concat((params.path as string[] | string | undefined) ?? []).filter(Boolean));
