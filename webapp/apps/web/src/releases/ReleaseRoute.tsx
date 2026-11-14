// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { useParams } from "@tanstack/react-router";
import { findRelease } from "../../shared/releases";
import { MissingReleasePage, ReleaseDetailPage } from "./ReleaseNotesPage";

/** /releases/$slug, its own module so release notes load only on release pages. */
export function ReleaseRoute() {
  const { slug } = useParams({ from: "/releases/$slug" });
  const release = findRelease(slug);
  return release ? <ReleaseDetailPage release={release} /> : <MissingReleasePage />;
}
