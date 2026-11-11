import { createRoot } from "react-dom/client";
import { AppRouter } from "./app/router";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <AppRouter />,
);
