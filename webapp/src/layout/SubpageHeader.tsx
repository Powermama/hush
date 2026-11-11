import type { ReactNode } from "react";
import { Header } from "./Header";

export function SubpageHeader({
  children,
  navigationLabel,
}: {
  children: ReactNode;
  navigationLabel: string;
}) {
  return (
    <Header navigationLabel={navigationLabel}>{children}</Header>
  );
}
