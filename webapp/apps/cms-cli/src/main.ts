#!/usr/bin/env bun
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { run } from "./cli";

process.exitCode = await run(process.argv.slice(2));
