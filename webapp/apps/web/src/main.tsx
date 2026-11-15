import { createRoot, hydrateRoot } from "react-dom/client";
import { RouterClient } from "@tanstack/react-router/ssr/client";
import { AppRouter, createAppRouter } from "./app/router";
import "./styles.css";

const root = document.getElementById("root")!;
const router = createAppRouter();
// Hydration needs the router's data from the prerendered page ($_TSR). Without
// it, hydrating would fail and React would remove the whole page, so the app
// renders fresh instead.
if (root.hasChildNodes() && (window as { $_TSR?: unknown }).$_TSR) {
  hydrateRoot(root, <RouterClient router={router} />);
} else {
  createRoot(root).render(<AppRouter router={router} />);
}
