// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { Fragment } from "react";

/** Renders a message's deliberate line breaks ("\n") as <br />, keeping each language's typographic rhythm. */
export function Lines({ text }: { text: string }) {
  const lines = text.split("\n");
  return <>{lines.map((line, index) => <Fragment key={index}>{index > 0 && <br />}{line}</Fragment>)}</>;
}
