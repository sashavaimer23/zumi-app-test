import { areaPage } from "../../lib/areas";
import { edgeCached } from "../../lib/cache";
export const onRequestGet: PagesFunction = ({ request, params }) =>
  edgeCached(request, 300, () => areaPage("rent", ([] as string[]).concat((params.path as string[] | string | undefined) ?? []).filter(Boolean)));
