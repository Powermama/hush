// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { createRequestHandler, renderRouterToString, RouterServer } from "@tanstack/react-router/ssr/server";
import { createAppRouter } from "./app/router";
import { extractLocaleFromUrl, overwriteGetLocale } from "./paraglide/runtime";

export async function render(url: string) {
  // Pages are prerendered one at a time, so the locale is set per render from
  // the URL (/de/... is German) for every message function on the page.
  const locale = extractLocaleFromUrl(url) ?? "en";
  overwriteGetLocale(() => locale);
  return createRequestHandler({ request: new Request(url), createRouter: createAppRouter })(
    ({ responseHeaders, router }) => renderRouterToString({
      router, responseHeaders,
      children: <html lang={locale}><head /><body><div id="root"><RouterServer router={router} /></div></body></html>,
    }),
  );
}
