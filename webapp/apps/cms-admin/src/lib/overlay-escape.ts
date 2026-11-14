// From Shade, Ghost Admin's design system (TryGhost/Ghost apps/shade/src, c2617d08),
// MIT License, Copyright (c) 2013-2026 Ghost Foundation (see packages/theme/LICENSE.ghost).
type OverlayEscapeHandler = (event: KeyboardEvent) => void;

/**
 * Lets Radix dismiss the active overlay while keeping the same Escape event
 * from reaching legacy document-level shells such as SettingsModal.
 */
const consumeOverlayEscape = (event: KeyboardEvent, onEscapeKeyDown?: OverlayEscapeHandler) => {
  onEscapeKeyDown?.(event);
  if (!event.defaultPrevented) {
    event.stopPropagation();
  }
};

export { consumeOverlayEscape };
