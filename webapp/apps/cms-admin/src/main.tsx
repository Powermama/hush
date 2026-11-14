// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { RouterProvider, createRouter } from "@tanstack/react-router";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import ShadeProvider from "@/providers/shade-provider";
import { routeTree } from "./routeTree.gen";
import { applyStoredTheme } from "@/components/theme-mode";
import "./index.css";

// Before the first render, so a dark preference never flashes light.
applyStoredTheme();

const queryClient = new QueryClient({ defaultOptions: { queries: { staleTime: 10_000 } } });
const router = createRouter({ routeTree, context: { queryClient }, defaultPreload: "intent", defaultPreloadStaleTime: 0, scrollRestoration: true });

declare module "@tanstack/react-router" {
  interface Register { router: typeof router }
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <ShadeProvider>
        <RouterProvider router={router} />
      </ShadeProvider>
    </QueryClientProvider>
  </StrictMode>,
);
