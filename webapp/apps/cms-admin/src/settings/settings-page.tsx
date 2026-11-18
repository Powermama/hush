// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The settings page, as Ghost Admin's (apps/admin/src/settings/layout:
// main-content.tsx, settings-sections.tsx; components/searchable-section.tsx,
// top-level-group.tsx; advanced/integrations.tsx): each group's title over its
// cards, the card in view marked in the navigation, Escape back to the app.
// hush has two sections: the owner's account and the API's integrations.
import { useQueryClient, useSuspenseQuery } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { formatDistanceToNowStrict, format } from "date-fns";
import { Check, Copy, KeyRound, Terminal } from "lucide-react";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { getListTokensQueryKey, revokeToken, useListTokens, type Token } from "@/api/cms.generated";
import { sessionQuery, signOut } from "@/api/session";
import { SettingGroup, SettingGroupActions, SettingGroupContent, SettingGroupDescription, SettingGroupDetails, SettingGroupHeader, SettingGroupTitle } from "@/components/patterns/setting-group";
import { ActionList, ActionListItem, ActionListItemActions, ActionListItemContent } from "@/components/ui/action-list";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useIsMobile } from "@/hooks/use-mobile";
import { cn } from "@/lib/utils";
import { settingsSections, useSettings, type SettingsSectionId } from "./settings-context";
import { NoSearchResult, SettingsHeader } from "./settings-nav";
import { latestEntry } from "@/lib/latest-entry";

/** One card, as Ghost's TopLevelGroup: title, description and buttons, then its content. */
function SettingsCard({ id, title, description, buttons, children }: {
  id: SettingsSectionId; title: string; description: ReactNode; buttons?: ReactNode; children?: ReactNode;
}) {
  const { isVisible, highlighted, setCurrent } = useSettings();
  const ref = useRef<HTMLDivElement>(null);
  // The card nearest the top of the page is the one in view.
  useEffect(() => {
    const element = ref.current;
    const scroller = document.getElementById("settings-scroller");
    if (!element || !scroller) return;
    const observer = new IntersectionObserver((entries) => { if (latestEntry(entries).isIntersecting) setCurrent(id); }, { root: scroller, rootMargin: "0px 0px -70% 0px" });
    observer.observe(element);
    return () => observer.disconnect();
  }, [id, setCurrent]);
  return (
    <SettingGroup ref={ref} id={`settings-${id}`} data-testid={id} highlighted={highlighted === id} className={cn("scroll-mt-10", !isVisible(id) && "hidden")}>
      <SettingGroupHeader>
        <SettingGroupDetails>
          <SettingGroupTitle>{title}</SettingGroupTitle>
          <SettingGroupDescription>{description}</SettingGroupDescription>
        </SettingGroupDetails>
        {buttons && <SettingGroupActions>{buttons}</SettingGroupActions>}
      </SettingGroupHeader>
      {children && <SettingGroupContent>{children}</SettingGroupContent>}
    </SettingGroup>
  );
}

/** A group's title over its cards, as Ghost's SearchableSection. */
function SettingsGroupSection({ title, children }: { title: string; children: ReactNode }) {
  const { isVisible } = useSettings();
  const visible = settingsSections.some((section) => section.group === title && isVisible(section.id));
  return (
    <div className={!visible ? "hidden" : undefined}>
      <h2 className="settings-heading z-20 mt-[-5px] mb-px pb-10 text-2xl leading-heading font-semibold tracking-tight">{title}</h2>
      <div className="flex flex-col gap-12">{children}</div>
    </div>
  );
}

function Account() {
  const { data: session } = useSuspenseQuery(sessionQuery);
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  return (
    <SettingsCard
      id="account" title="Account" description="You sign in to the CMS with GitHub."
      buttons={<Button size="sm" variant="ghost" className="mt-[-5px]" onClick={async () => { await signOut(); queryClient.clear(); void navigate({ to: "/sign-in" }); }}>Sign out</Button>}
    >
      <dl className="grid gap-x-8 gap-y-6 md:grid-cols-2">
        <div><dt className="text-base font-semibold">Signed in as</dt><dd className="mt-1 text-muted-foreground">@{session.login}, the owner</dd></div>
        <div><dt className="text-base font-semibold">Session</dt><dd className="mt-1 text-muted-foreground">Ends after 12 hours without use, or after 7 days</dd></div>
      </dl>
    </SettingsCard>
  );
}

const scopeNames: Record<string, string> = { "posts:read": "read", "posts:write": "write", "posts:publish": "publish" };

function tokenDetail(token: Token) {
  const scopes = token.scopes.map((scope) => scopeNames[scope] ?? scope).join(", ");
  const used = token.lastUsedAt ? `last used ${formatDistanceToNowStrict(new Date(token.lastUsedAt), { addSuffix: true })}` : "never used";
  const expires = !token.expiresAt ? "does not expire"
    : new Date(token.expiresAt) < new Date() ? "expired" : `expires ${format(new Date(token.expiresAt), "d MMM yyyy")}`;
  return `${scopes.charAt(0).toUpperCase()}${scopes.slice(1)} · ${used} · ${expires}`;
}

function ConnectCliDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const [copied, setCopied] = useState(false);
  const command = "hush-cms auth login";
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Connect the CLI</DialogTitle>
          <DialogDescription>On the Mac that should use the CMS, run:</DialogDescription>
        </DialogHeader>
        <div className="flex items-center gap-2 rounded-md border border-border-default bg-muted/50 py-1 pr-1 pl-3">
          <code className="grow font-mono text-sm">{command}</code>
          <Button size="sm" variant="ghost" onClick={() => { void navigator.clipboard.writeText(command); setCopied(true); setTimeout(() => setCopied(false), 2000); }}>
            {copied ? <><Check />Copied</> : <><Copy />Copy</>}
          </Button>
        </div>
        <p className="text-sm text-muted-foreground">It shows a code and opens this CMS, where you check the code and click Authorize. The CLI keeps its token in the Mac's Keychain; it appears here once connected.</p>
      </DialogContent>
    </Dialog>
  );
}

function Integrations() {
  const tokens = useListTokens();
  const queryClient = useQueryClient();
  const [connecting, setConnecting] = useState(false);
  const [revoking, setRevoking] = useState<Token>();
  const list = tokens.data?.status === 200 ? tokens.data.data.tokens : [];
  const revoke = async (token: Token) => {
    await revokeToken(token.id);
    await queryClient.invalidateQueries({ queryKey: getListTokensQueryKey() });
  };
  return (
    <SettingsCard
      id="integrations" title="Integrations" description="Connect the hush-cms command line and services to the CMS API."
      buttons={<Button size="sm" variant="ghost" className="mt-[-5px]" onClick={() => setConnecting(true)}>Connect CLI</Button>}
    >
      {tokens.isSuccess && !list.length ? (
        <p className="text-muted-foreground">No tokens yet. Connect the CLI to get one.</p>
      ) : (
        <ActionList aria-label="Tokens">
          {list.map((token) => (
            <ActionListItem key={token.id} data-testid="token">
              <ActionListItemContent className="flex w-full items-center gap-3 py-3">
                <span className="flex size-8 shrink-0 items-center justify-center rounded-md bg-muted text-muted-foreground [&_svg]:size-4">
                  {token.kind === "device" ? <Terminal /> : <KeyRound />}
                </span>
                <span className="min-w-0 grow">
                  <span className="flex items-center gap-1 font-medium">{token.name}</span>
                  <span className="block text-sm text-muted-foreground">{tokenDetail(token)}</span>
                </span>
              </ActionListItemContent>
              <ActionListItemActions visibility="hover">
                <Button size="sm" type="button" variant="destructive-ghost" onClick={() => setRevoking(token)}>Revoke</Button>
              </ActionListItemActions>
            </ActionListItem>
          ))}
        </ActionList>
      )}
      <ConnectCliDialog open={connecting} onOpenChange={setConnecting} />
      <AlertDialog open={Boolean(revoking)} onOpenChange={(open) => { if (!open) setRevoking(undefined); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Revoke token?</AlertDialogTitle>
            <AlertDialogDescription>
              {revoking?.kind === "device"
                ? <>{revoking.name} loses access at once. Run <code className="font-mono whitespace-nowrap">hush-cms auth login</code> there to connect it again.</>
                : `${revoking?.name} loses access at once. Anything using it stops working until it gets a new token.`}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction variant="destructive" onClick={() => { if (revoking) void revoke(revoking); }}>Revoke</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </SettingsCard>
  );
}

export function SettingsPage({ section }: { section?: SettingsSectionId }) {
  const navigate = useNavigate();
  const isMobile = useIsMobile();
  const { isVisible, jumpTo } = useSettings();
  const noResult = settingsSections.every((item) => !isVisible(item.id));

  // A link to a section opens at it.
  useEffect(() => { if (section) jumpTo(section); }, [section, jumpTo]);
  // Escape leaves Settings, unless a dialog or a field with text takes it. Checked in
  // the capture phase, before a dialog closes itself on the same key.
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || document.querySelector(':is([role="dialog"], [role="alertdialog"])[data-state="open"]')) return;
      const target = event.target as HTMLElement;
      if ((target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement) && target.value) return;
      void navigate({ to: "/" });
    };
    window.addEventListener("keydown", onKeyDown, true);
    return () => window.removeEventListener("keydown", onKeyDown, true);
  }, [navigate]);

  // On a phone the page carries the header and the no-result message; on a desktop the sidebar does.
  return (
    <div className="flex h-full min-h-0 flex-col">
      {isMobile && <SettingsHeader className="shrink-0 px-8 pt-4 pb-2" />}
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-y-contain" id="settings-scroller">
        {isMobile && noResult && <NoSearchResult className="mx-auto max-w-[760px] px-8 pt-8" />}
        <div className="mx-auto flex max-w-[760px] flex-col gap-16 px-8 py-16 tablet:px-(--page-gutter)">
          <SettingsGroupSection title="General settings"><Account /></SettingsGroupSection>
          <SettingsGroupSection title="Advanced"><Integrations /></SettingsGroupSection>
        </div>
      </div>
    </div>
  );
}
