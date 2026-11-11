// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { createRequestHandler, renderRouterToString, RouterServer } from "@tanstack/react-router/ssr/server";
import { createAppRouter } from "./app/router";

export async function render(url: string) {
  return createRequestHandler({ request: new Request(url), createRouter: createAppRouter })(
    ({ responseHeaders, router }) => renderRouterToString({
      router, responseHeaders,
      children: <html lang="en"><head /><body><div id="root"><RouterServer router={router} /></div></body></html>,
    }),
  );
}
