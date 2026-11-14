// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { Landing } from "./Landing";

/** /de, its own module so the router loads the landing only on landing pages. */
export function GermanLanding() {
  return <Landing lang="de" />;
}
