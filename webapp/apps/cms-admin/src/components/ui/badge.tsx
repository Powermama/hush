// From Shade, Ghost Admin's design system (TryGhost/Ghost apps/shade/src, c2617d08),
// MIT License, Copyright (c) 2013-2026 Ghost Foundation (see packages/theme/LICENSE.ghost).
import * as React from 'react';
import { Slot as SlotPrimitive } from 'radix-ui';
import { type VariantProps } from 'class-variance-authority';

import { badgeVariants } from '@/components/ui/badge-variants';
import { useShade } from '@/providers/shade-context';
import { cn } from '@/lib/utils';

export interface BadgeProps
  extends React.HTMLAttributes<HTMLDivElement>, VariantProps<typeof badgeVariants> {
  asChild?: boolean;
}

function Badge({ className, shape, size, variant, asChild = false, ...props }: BadgeProps) {
  const { controlShape } = useShade();
  const Comp = asChild ? SlotPrimitive.Root : 'div';
  return (
    <Comp
      className={cn(badgeVariants({ shape: shape ?? controlShape, size, variant }), className)}
      {...props}
    />
  );
}

export { Badge };
