// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { createFileRoute } from "@tanstack/react-router";
import { settingsSections, type SettingsSectionId } from "@/settings/settings-context";
import { SettingsPage } from "@/settings/settings-page";

/** /settings, or /settings/<section> to open at a section, as Ghost's /settings/integrations. */
export const Route = createFileRoute("/_app/settings/{-$section}")({ component: Settings });

function Settings() {
  const { section } = Route.useParams();
  const known = settingsSections.some((item) => item.id === section) ? (section as SettingsSectionId) : undefined;
  return <SettingsPage section={known} />;
}
