// From Shade, Ghost Admin's design system (TryGhost/Ghost apps/shade/src, c2617d08),
// MIT License, Copyright (c) 2013-2026 Ghost Foundation (see packages/theme/LICENSE.ghost).
import { cva } from 'class-variance-authority';

const settingGroupVariants = cva(
  'group/setting-group relative flex flex-col gap-6 rounded-card text-card-foreground transition-all',
  {
    variants: {
      variant: {
        outline: 'border border-border-default bg-card p-5 hover:shadow-sm md:p-7',
        plain: 'bg-transparent',
      },
      highlighted: {
        true: 'shadow-sm',
        false: '',
      },
    },
    defaultVariants: {
      variant: 'outline',
      highlighted: false,
    },
  },
);

export { settingGroupVariants };
