// From Shade, Ghost Admin's design system (TryGhost/Ghost apps/shade/src, c2617d08),
// MIT License, Copyright (c) 2013-2026 Ghost Foundation (see packages/theme/LICENSE.ghost).
// Slimmed for the hush admin: no dirty-state provider, no text-field focus tracking,
// and the three toast icons are inlined from apps/shade/src/assets/icons.
import React, { useEffect, useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import { Toaster } from '@/components/ui/sonner';
import { TooltipProvider } from '@/components/ui/tooltip';
import { ShadeScope } from '@/shade-scope';
import { ShadeContext } from '@/providers/shade-context';

const ToastIcon = ({ className, d }: { className: string; d: string }) => (
  <svg aria-hidden="true" className={`size-4 ${className}`} viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
    <path d={d} fill="currentColor" />
  </svg>
);

const ERROR_FILL =
  'm23.77 20.57 -10 -19A2 2 0 0 0 12 0.5a2 2 0 0 0 -1.77 1.07l-10 19a2 2 0 0 0 0.06 2A2 2 0 0 0 2 23.5h20a2 2 0 0 0 1.77 -2.93ZM11 8.5a1 1 0 0 1 2 0v6a1 1 0 0 1 -2 0ZM12.05 20a1.53 1.53 0 0 1 -1.52 -1.47A1.48 1.48 0 0 1 12 17a1.53 1.53 0 0 1 1.52 1.47A1.48 1.48 0 0 1 12.05 20Z';
const SUCCESS_FILL =
  'M12 0a12 12 0 1 0 12 12A12 12 0 0 0 12 0Zm6.93 8.2 -6.85 9.29a1 1 0 0 1 -1.43 0.19l-4.89 -3.91a1 1 0 0 1 -0.15 -1.41A1 1 0 0 1 7 12.21l4.08 3.26L17.32 7a1 1 0 0 1 1.39 -0.21 1 1 0 0 1 0.22 1.41Z';
const INFO_FILL =
  'M12 0a12 12 0 1 0 12 12A12 12 0 0 0 12 0Zm0.25 5a1.5 1.5 0 1 1 -1.5 1.5 1.5 1.5 0 0 1 1.5 -1.5Zm2.25 13.5h-4a1 1 0 0 1 0 -2h0.75a0.25 0.25 0 0 0 0.25 -0.25v-4.5a0.25 0.25 0 0 0 -0.25 -0.25h-0.75a1 1 0 0 1 0 -2h1a2 2 0 0 1 2 2v4.75a0.25 0.25 0 0 0 0.25 0.25h0.75a1 1 0 0 1 0 2Z';

const ToasterPortal = () => {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
    return () => setMounted(false);
  }, []);

  return mounted
    ? createPortal(
        <ShadeScope style={{ width: 'unset', height: 'unset' }}>
          <Toaster
            duration={5000}
            icons={{
              error: <ToastIcon className="text-red" d={ERROR_FILL} />,
              success: <ToastIcon className="text-green" d={SUCCESS_FILL} />,
              info: <ToastIcon className="text-text-tertiary" d={INFO_FILL} />,
            }}
            position="bottom-left"
            toastOptions={{
              classNames: {
                title: 'mt-[-1px]! text-md! font-semibold! leading-tighter! tracking-[0.1px]!',
                description: 'text-text-primary! text-sm! mt-px!',
                icon: 'ml-0!',
              },
              style: {
                alignItems: 'flex-start',
                maxWidth: '290px',
              },
            }}
            closeButton
          />
        </ShadeScope>,
        document.body,
      )
    : null;
};

interface ShadeProviderProps {
  children: React.ReactNode;
}

const isDark = () => document.documentElement.classList.contains('dark');

/** Follows the `dark` class that theme-mode.ts sets on <html>. */
const useDarkMode = () => {
  const [darkMode, setDarkMode] = useState(isDark);

  useEffect(() => {
    const observer = new MutationObserver(() => setDarkMode(isDark()));
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });
    return () => observer.disconnect();
  }, []);

  return darkMode;
};

/** Ghost Admin's shipping design: admin7Design off, pill-shaped controls. */
const ShadeProvider: React.FC<ShadeProviderProps> = ({ children }) => {
  const darkMode = useDarkMode();
  const value = useMemo(
    () => ({
      isAnyTextFieldFocused: false,
      setFocusState: () => {},
      darkMode,
      admin7Design: false,
      controlShape: 'pill' as const,
    }),
    [darkMode],
  );

  return (
    <ShadeContext.Provider value={value}>
      {/* Default Radix tooltip timing for any Tooltip without a nearer
          provider; inner providers still win via nearest-provider scoping. */}
      <TooltipProvider>
        {children}
        <ToasterPortal />
      </TooltipProvider>
    </ShadeContext.Provider>
  );
};

export default ShadeProvider;
