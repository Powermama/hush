// From Shade, Ghost Admin's design system (TryGhost/Ghost apps/shade/src, c2617d08),
// MIT License, Copyright (c) 2013-2026 Ghost Foundation (see packages/theme/LICENSE.ghost).
import { cva } from 'class-variance-authority';

const previewChromeVariants = cva('size-full', {
  variants: {
    device: {
      desktop: 'px-8',
      mobile: 'h-[775px] w-[380px] rounded-3xl bg-surface-elevated p-2 shadow-xl',
    },
  },
  defaultVariants: {
    device: 'desktop',
  },
});

export { previewChromeVariants };
