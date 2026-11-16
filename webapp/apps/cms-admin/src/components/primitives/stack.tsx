// From Shade, Ghost Admin's design system (TryGhost/Ghost apps/shade/src, c2617d08),
// MIT License, Copyright (c) 2013-2026 Ghost Foundation (see packages/theme/LICENSE.ghost).
import { cn } from '@/lib/utils';
import {
  ALIGN_ITEMS_CLASSES,
  GAP_CLASSES,
  JUSTIFY_CONTENT_CLASSES,
  Align,
  Justify,
  SpaceStep,
} from './types';
import React from 'react';

export interface StackProps extends React.HTMLAttributes<HTMLDivElement> {
  gap?: SpaceStep;
  align?: Align;
  justify?: Justify;
}

const Stack = React.forwardRef<HTMLDivElement, StackProps>(function Stack(
  { className, gap = 'md', align = 'stretch', justify = 'start', ...props }: StackProps,
  ref,
) {
  return (
    <div
      ref={ref}
      className={cn(
        'flex flex-col',
        GAP_CLASSES[gap],
        ALIGN_ITEMS_CLASSES[align],
        JUSTIFY_CONTENT_CLASSES[justify],
        className,
      )}
      {...props}
    />
  );
});

Stack.displayName = 'Stack';

export { Stack };
