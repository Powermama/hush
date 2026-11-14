// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { useParams } from "@tanstack/react-router";
import { ProofPage } from "./ProofPage";

/** /p/$slug, its own module so the proof code loads only on proof pages. */
export function ProofRoute() {
  const { slug } = useParams({ from: "/p/$slug" });
  return <ProofPage slug={slug} />;
}
