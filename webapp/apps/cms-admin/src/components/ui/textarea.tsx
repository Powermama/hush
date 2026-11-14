// From Shade, Ghost Admin's design system (TryGhost/Ghost apps/shade/src, c2617d08),
// MIT License, Copyright (c) 2013-2026 Ghost Foundation (see packages/theme/LICENSE.ghost).
import * as React from 'react';

import { cn } from '@/lib/utils';
import { inputSurface, inputSurfaceClasses } from '@/components/ui/input-surface';

const Textarea = React.forwardRef<HTMLTextAreaElement, React.ComponentProps<'textarea'>>(
  ({ className, ...props }, ref) => {
    return (
      <textarea
        ref={ref}
        className={cn(
          inputSurface('self'),
          inputSurfaceClasses.disabledFieldSelf,
          'flex min-h-[80px] w-full max-w-none px-3 py-2 text-(length:--text-field) placeholder:text-muted-foreground',
          className,
        )}
        {...props}
      />
    );
  },
);
Textarea.displayName = 'Textarea';

export { Textarea };
