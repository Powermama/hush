// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Where the CLI keeps its token: the macOS Keychain, one item per CMS origin.
// HUSH_CMS_TOKEN overrides it, for CI and machines without a Keychain. The
// token never appears in arguments, so it stays out of shell history and `ps`.
const service = "hush-cms";

export const tokenPattern = /^hcms_[A-Za-z0-9_-]{20,}$/;

export class CredentialError extends Error {}

const hasKeychain = () => process.platform === "darwin";

/** The token for `origin`: HUSH_CMS_TOKEN, else the Keychain item, else undefined. */
export async function readToken(origin: string): Promise<{ token: string; source: "environment" | "keychain" } | undefined> {
  const fromEnvironment = process.env.HUSH_CMS_TOKEN;
  if (fromEnvironment) return { token: fromEnvironment, source: "environment" };
  const stored = storedToken(origin);
  return stored ? { token: stored, source: "keychain" } : undefined;
}

/** The Keychain item alone, whatever HUSH_CMS_TOKEN says. */
export function storedToken(origin: string) {
  if (!hasKeychain()) return undefined;
  const found = Bun.spawnSync(["security", "find-generic-password", "-s", service, "-a", origin, "-w"], { stderr: "ignore" });
  // 44: no such item.
  if (found.exitCode === 44) return undefined;
  if (found.exitCode !== 0) throw new CredentialError("The Keychain refused to read the token.");
  return found.stdout.toString().trim() || undefined;
}

export async function saveToken(origin: string, token: string) {
  if (!hasKeychain()) throw new CredentialError("Only macOS has a Keychain here; set HUSH_CMS_TOKEN instead.");
  if (!tokenPattern.test(token)) throw new CredentialError("That is not a CMS token (they start with hcms_).");
  // `security -i` reads the command from stdin, so the token is never an argument.
  const saved = Bun.spawnSync(["security", "-i"], {
    stdin: new TextEncoder().encode(`add-generic-password -U -s ${service} -a ${origin} -l "hush CMS token" -w ${token}\n`),
    stdout: "ignore", stderr: "pipe",
  });
  if (saved.exitCode !== 0 || saved.stderr.length) throw new CredentialError("The Keychain refused to store the token.");
}

/** Removes the Keychain item; false when there was none. */
export function deleteToken(origin: string) {
  if (!hasKeychain()) return false;
  return Bun.spawnSync(["security", "delete-generic-password", "-s", service, "-a", origin], { stdout: "ignore", stderr: "ignore" }).exitCode === 0;
}

/** Reads a token without echoing it: a hidden prompt on a terminal, else all of stdin. */
export async function promptToken(): Promise<string> {
  if (!process.stdin.isTTY) return (await new Response(Bun.stdin.stream()).text()).trim();
  process.stderr.write("Paste the CMS token (input is hidden): ");
  process.stdin.setRawMode(true);
  process.stdin.resume();
  try {
    return await new Promise<string>((resolve, reject) => {
      let typed = "";
      process.stdin.on("data", (chunk: Buffer) => {
        for (const character of chunk.toString("utf8")) {
          if (character === "\r" || character === "\n") return resolve(typed.trim());
          if (character === "\u0003") return reject(new CredentialError("Cancelled."));
          typed = character === "\u007f" ? typed.slice(0, -1) : typed + character;
        }
      });
    });
  } finally {
    process.stdin.setRawMode(false);
    process.stdin.pause();
    process.stderr.write("\n");
  }
}
