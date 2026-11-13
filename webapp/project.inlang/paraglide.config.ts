// Paraglide compiler options, shared by the Vite plugin and `paraglide-js compile`.
// Locales come from the URL: /de/... is German, everything else English.
export default {
  outdir: "./src/paraglide",
  emitTsDeclarations: true,
  strategy: ["url", "baseLocale"],
} satisfies { outdir: string; emitTsDeclarations: boolean; strategy: Array<"url" | "baseLocale"> };
