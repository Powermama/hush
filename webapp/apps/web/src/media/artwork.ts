// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
// Colour treatments are baked into these files by scripts/bake-artwork.mjs.
// Pages must not reapply them as CSS or SVG filters: WebKit renders filters on
// the CPU in its GPU process and stalls WebGL frame delivery meanwhile.
import aristotle from "./art/aristotle-blue.webp?url";
import aristotleSmall from "./art/aristotle-blue-small.webp?url";
import liberty from "./art/liberty-coral.webp?url";
import libertySmall from "./art/liberty-coral-small.webp?url";
import libertyEcho from "./art/liberty-coral-echo.webp?url";
import geographer from "./art/geographer-muted.webp?url";
import geographerSmall from "./art/geographer-muted-small.webp?url";
import printingPress from "./art/printing-press-print.webp?url";
import printingPressSmall from "./art/printing-press-print-small.webp?url";
import printingPressEcho from "./art/printing-press-print-echo.webp?url";
import printingPressEchoSmall from "./art/printing-press-print-echo-small.webp?url";
import twitteringMachine from "./art/twittering-machine-muted.webp?url";
import twitteringMachineSmall from "./art/twittering-machine-muted-small.webp?url";
import robotPortrait from "./art/robot-portrait-teal.webp?url";
import robotPortraitSmall from "./art/robot-portrait-teal-small.webp?url";

// Explicit imports let Vite version images in both client and prerendered HTML.
// Attribution remains public at /art/CREDITS.md.
export const artwork = {
  aristotle: { src: aristotle, srcSet: `${aristotleSmall} 480w, ${aristotle} 960w` },
  liberty: { src: liberty, srcSet: `${libertySmall} 768w, ${liberty} 1280w` },
  libertyEcho: { src: libertyEcho },
  geographer: { src: geographer, srcSet: `${geographerSmall} 480w, ${geographer} 960w` },
  printingPress: { src: printingPress, srcSet: `${printingPressSmall} 450w, ${printingPress} 751w` },
  printingPressEcho: { src: printingPressEcho, srcSet: `${printingPressEchoSmall} 450w, ${printingPressEcho} 751w` },
  twitteringMachine: { src: twitteringMachine, srcSet: `${twitteringMachineSmall} 480w, ${twitteringMachine} 994w` },
  robotPortrait: { src: robotPortrait, srcSet: `${robotPortraitSmall} 480w, ${robotPortrait} 780w` },
};
