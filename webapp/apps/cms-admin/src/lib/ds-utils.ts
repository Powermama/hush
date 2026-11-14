// From Shade, Ghost Admin's design system (TryGhost/Ghost apps/shade/src, c2617d08),
// MIT License, Copyright (c) 2013-2026 Ghost Foundation (see packages/theme/LICENSE.ghost).
// Only the helpers the ported components use.

const stringHash = (str: string) => {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = str.charCodeAt(i) + ((hash << 5) - hash);
  }
  return hash;
};

export const stringToHslColor = (str: string, saturation: string, lightness: string) => {
  const h = stringHash(str) % 360;
  return 'hsl(' + h + ', ' + saturation + '%, ' + lightness + '%)';
};

// Tonal pairings (Shapeshifter style): a palette family's 200 behind its 800,
// reversed in dark mode.
// Written out in full so Tailwind generates every class.
const TONAL_AVATAR_CLASSES = [
  'bg-red-200 text-red-800 dark:bg-red-800 dark:text-red-200',
  'bg-orange-200 text-orange-800 dark:bg-orange-800 dark:text-orange-200',
  'bg-yellow-200 text-yellow-800 dark:bg-yellow-800 dark:text-yellow-200',
  'bg-green-200 text-green-800 dark:bg-green-800 dark:text-green-200',
  'bg-blue-200 text-blue-800 dark:bg-blue-800 dark:text-blue-200',
  'bg-purple-200 text-purple-800 dark:bg-purple-800 dark:text-purple-200',
  'bg-pink-200 text-pink-800 dark:bg-pink-800 dark:text-pink-200',
];

/** The admin7Design initials avatar colours: one palette family picked by the string's hash. */
export const stringToTonalAvatarClasses = (str: string) =>
  TONAL_AVATAR_CLASSES[Math.abs(stringHash(str)) % TONAL_AVATAR_CLASSES.length];
