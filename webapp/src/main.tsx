import { createRoot, hydrateRoot } from "react-dom/client";
import { RouterClient } from "@tanstack/react-router/ssr/client";
import { AppRouter, createAppRouter } from "./app/router";
import "./styles.css";

const root = document.getElementById("root")!;
const router = createAppRouter();
if (root.hasChildNodes()) {
  hydrateRoot(root, <RouterClient router={router} />);
} else {
  createRoot(root).render(<AppRouter router={router} />);
}
