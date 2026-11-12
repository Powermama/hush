// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import aristotle from "./art/aristotle.webp?url";
import aristotleSmall from "./art/aristotle-small.webp?url";
import liberty from "./art/liberty.webp?url";
import libertySmall from "./art/liberty-small.webp?url";
import geographer from "./art/geographer.webp?url";
import geographerSmall from "./art/geographer-small.webp?url";
import printingPress from "./art/printing-press.webp?url";
import printingPressSmall from "./art/printing-press-small.webp?url";
import twitteringMachine from "./art/twittering-machine.webp?url";
import twitteringMachineSmall from "./art/twittering-machine-small.webp?url";
import robotPortrait from "./art/robot-portrait.webp?url";
import robotPortraitSmall from "./art/robot-portrait-small.webp?url";

// Explicit imports let Vite version images in both client and prerendered HTML.
// Attribution remains public at /art/CREDITS.md.
export const artwork = {
  aristotle: { src: aristotle, srcSet: `${aristotleSmall} 480w, ${aristotle} 960w` },
  liberty: { src: liberty, srcSet: `${libertySmall} 768w, ${liberty} 1280w` },
  geographer: { src: geographer, srcSet: `${geographerSmall} 480w, ${geographer} 960w` },
  printingPress: { src: printingPress, srcSet: `${printingPressSmall} 450w, ${printingPress} 751w` },
  twitteringMachine: { src: twitteringMachine, srcSet: `${twitteringMachineSmall} 480w, ${twitteringMachine} 994w` },
  robotPortrait: { src: robotPortrait, srcSet: `${robotPortraitSmall} 480w, ${robotPortrait} 780w` },
};
