// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The signed-in screens with Ghost Admin's shell (apps/admin/src/layout/admin-layout.tsx,
// app-sidebar): a floating sidebar card with the site identity, View site, Posts
// with its views and the "+" for a new post, and the user menu at the bottom.
// The editor (_editor) has no shell, as in Ghost.
import { useQueryClient, useSuspenseQuery } from "@tanstack/react-query";
import { Link, Outlet, createFileRoute, useNavigate, useRouterState } from "@tanstack/react-router";
import { AppWindow, Check, ChevronRight, ChevronsUpDown, Ellipsis, ExternalLink, LogOut, Monitor, Moon, Palette, PenLine, Plus, Sun } from "lucide-react";
import { useState, type CSSProperties } from "react";
import { requireSession } from "@/api/require-session";
import { sessionQuery, signOut } from "@/api/session";
import { HushLogo } from "@/components/hush-logo";
import { useThemeMode, type ThemeMode } from "@/components/theme-mode";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuSub,
  DropdownMenuSubContent, DropdownMenuSubTrigger, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Sidebar, SidebarContent, SidebarFooter, SidebarGroup, SidebarHeader, SidebarInset, SidebarMenu, SidebarMenuButton,
  SidebarMenuItem, SidebarProvider, SidebarTrigger,
} from "@/components/ui/sidebar";
import { useSidebar } from "@/components/ui/sidebar-context";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_app")({
  beforeLoad: requireSession,
  component: AppLayout,
});

const views = [
  { status: "draft", label: "Drafts" },
  { status: "scheduled", label: "Scheduled" },
  { status: "published", label: "Published" },
] as const;

/** Navigating from the sidebar's sheet closes it, as in Ghost (app-sidebar/nav-menu-item.tsx). */
function useCloseMobileSidebar() {
  const { isMobile, setOpenMobile } = useSidebar();
  return () => { if (isMobile) setOpenMobile(false); };
}

function SiteIdentity() {
  const close = useCloseMobileSidebar();
  return (
    <Link to="/" aria-label="hush CMS, posts" onClick={close} className="flex w-full min-w-0 items-center gap-2 text-foreground">
      <HushLogo withName={false} className="[&_svg]:size-8" />
      <span className="heading-font-features min-w-0 truncate text-lg font-semibold text-foreground">hush</span>
    </Link>
  );
}

function PostsNav() {
  const close = useCloseMobileSidebar();
  const { location } = useRouterState();
  const status = (location.search as { status?: string }).status;
  const onPosts = location.pathname === "/";
  const [open, setOpen] = useState(true);
  return (
    <SidebarMenuItem>
      <SidebarMenuButton asChild isActive={onPosts && !status}>
        <Link to="/" search={{}} onClick={close} className="group/posts">
          {/* On hover the icon gives way to the expand chevron, as in Ghost. */}
          <PenLine className="sidebar:group-hover/menu-item:opacity-0" />
          <span>Posts</span>
        </Link>
      </SidebarMenuButton>
      <button
        type="button" aria-label={open ? "Hide post views" : "Show post views"} aria-expanded={open} onClick={() => setOpen((value) => !value)}
        className="absolute top-0 left-3 flex h-(--control-height) items-center text-sidebar-foreground opacity-0 transition-opacity group-hover/menu-item:opacity-100 focus-visible:opacity-100"
      >
        <ChevronRight size={16} strokeWidth={1.5} className={cn("transition-transform", open && "rotate-90")} />
      </button>
      <Link
        to="/posts/$id" params={{ id: "new" }} aria-label="New post" onClick={close}
        className="absolute top-0 right-0 flex size-8 items-center justify-center rounded-full p-0 text-gray-700 ring-sidebar-ring outline-hidden transition-all hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 dark:text-gray-800 dark:hover:text-white"
      >
        <Plus className="mt-px stroke-[1.5px]!" size={20} />
      </Link>
      <div className={cn("grid transition-all duration-200 ease-out", open ? "grid-rows-[1fr]" : "-mb-px grid-rows-[0fr]")}>
        <ul className="flex min-h-0 flex-col gap-px overflow-hidden">
          {views.map((view) => (
            <li key={view.status} className="relative before:absolute before:inset-y-0 before:left-5 before:z-10 before:w-px before:bg-sidebar-accent">
              <div className="min-w-0 pl-7">
                <SidebarMenuButton asChild isActive={onPosts && status === view.status}>
                  <Link to="/" search={{ status: view.status }} onClick={close} className="w-full min-w-0 pl-2"><span>{view.label}</span></Link>
                </SidebarMenuButton>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </SidebarMenuItem>
  );
}

const modes: Array<{ mode: ThemeMode; label: string; icon: typeof Sun }> = [
  { mode: "dark", label: "Dark", icon: Moon },
  { mode: "light", label: "Light", icon: Sun },
  { mode: "system", label: "System", icon: Monitor },
];

function UserMenu() {
  const { data: session } = useSuspenseQuery(sessionQuery);
  const [mode, setMode] = useThemeMode();
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const initial = session.login.slice(0, 1).toUpperCase();
  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <SidebarMenuButton size="lg">
              <span aria-hidden className="flex size-8 shrink-0 items-center justify-center rounded-full bg-gray-900 text-sm font-semibold text-white dark:bg-gray-200 dark:text-gray-950">{initial}</span>
              <div className="grid flex-1 text-left text-base leading-tight">
                <span className="truncate font-semibold">{session.login}</span>
                <span className="-mt-px truncate text-sm text-muted-foreground">Owner, via GitHub</span>
              </div>
              <ChevronsUpDown className="ml-auto size-4 text-gray-700" />
            </SidebarMenuButton>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" sideOffset={10} className="w-[var(--radix-dropdown-menu-trigger-width)]">
            <DropdownMenuLabel className="font-normal">
              <span className="block truncate font-semibold">{session.login}</span>
              <span className="block truncate text-sm text-muted-foreground">Signed in with GitHub</span>
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuSub>
              <DropdownMenuSubTrigger><Palette />Appearance</DropdownMenuSubTrigger>
              <DropdownMenuSubContent>
                {modes.map(({ mode: option, label, icon: Icon }) => (
                  <DropdownMenuItem key={option} onSelect={() => setMode(option)}>
                    <Icon />{label}{mode === option && <Check className="ml-auto" />}
                  </DropdownMenuItem>
                ))}
              </DropdownMenuSubContent>
            </DropdownMenuSub>
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={async () => { await signOut(); queryClient.clear(); await navigate({ to: "/sign-in" }); }}>
              <LogOut />Sign out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </SidebarMenuItem>
    </SidebarMenu>
  );
}

const mobileNavButton = "w-full max-w-16 min-w-9 rounded-full hover:bg-sidebar-accent hover:text-sidebar-accent-foreground";

/** Ghost's bottom bar below 801px (layout/app-sidebar/mobile-nav-bar.tsx): the main screens, then the sidebar as a sheet. */
function MobileNavBar() {
  const { isMobile } = useSidebar();
  const onPosts = useRouterState({ select: (state) => state.location.pathname === "/" });
  if (!isMobile) return null;
  return (
    <div className="fixed inset-x-0 bottom-0 z-50 h-(--mobile-navbar-height) border-t border-sidebar-border bg-sidebar/80 pb-[env(safe-area-inset-bottom)] backdrop-blur-md sidebar:hidden">
      <div className="mx-auto grid size-full max-w-[225px] grid-cols-3 items-center justify-items-center px-5">
        <Button asChild size="icon" variant="ghost" data-active={onPosts} className={cn(mobileNavButton, onPosts ? "bg-sidebar-accent text-sidebar-accent-foreground" : "bg-transparent")}>
          <Link to="/" search={{}}><PenLine strokeWidth={1.5} /><span className="sr-only">Posts</span></Link>
        </Button>
        <Button asChild size="icon" variant="ghost" className={cn(mobileNavButton, "bg-transparent")}>
          <a href="https://behu.sh/blog" target="_blank" rel="noreferrer"><AppWindow strokeWidth={1.5} /><span className="sr-only">View site</span></a>
        </Button>
        <SidebarTrigger className="h-9 rounded-full px-8 hover:bg-transparent">
          <Ellipsis strokeWidth={1.5} />
          <span className="sr-only">Toggle Sidebar</span>
        </SidebarTrigger>
      </div>
    </div>
  );
}

function AppLayout() {
  return (
    <SidebarProvider
      style={{ "--sidebar-width": "316px" } as CSSProperties}
      className="h-dvh [--content-width:1080px] [--page-gutter:20px] sidebar:[--page-gutter:40px] min-[1380px]:[--content-width:1280px] [&_[data-sidebar=sidebar]]:rounded-xl [&_[data-sidebar=sidebar]]:border-border [&_[data-sidebar=sidebar]]:shadow-none"
    >
      <Sidebar variant="floating">
        <SidebarHeader className="px-5 pt-5 pb-0">
          <SiteIdentity />
        </SidebarHeader>
        <SidebarContent className="justify-between px-3 pt-4 pb-1">
          <div className="flex flex-col gap-2 sidebar:gap-4">
            <SidebarGroup>
              <SidebarMenu>
                <SidebarMenuItem className="group/viewsite">
                  <SidebarMenuButton asChild>
                    <a href="https://behu.sh/blog" target="_blank" rel="noreferrer"><AppWindow /><span>View site</span></a>
                  </SidebarMenuButton>
                  <a
                    href="https://behu.sh/blog" target="_blank" rel="noreferrer" aria-label="Open behu.sh in a new tab"
                    className="absolute top-0 right-0 flex size-8 items-center justify-center rounded-full text-gray-700 opacity-0 group-hover/viewsite:opacity-100 hover:bg-sidebar-accent focus-visible:opacity-100"
                  >
                    <ExternalLink size={16} />
                  </a>
                </SidebarMenuItem>
              </SidebarMenu>
            </SidebarGroup>
            <SidebarGroup>
              <SidebarMenu><PostsNav /></SidebarMenu>
            </SidebarGroup>
          </div>
        </SidebarContent>
        <SidebarFooter className="gap-0 p-3"><UserMenu /></SidebarFooter>
      </Sidebar>
      <SidebarInset className="relative max-h-[calc(100%-var(--mobile-navbar-height))] overflow-y-auto bg-background sidebar:max-h-full">
        <Outlet />
        <MobileNavBar />
      </SidebarInset>
    </SidebarProvider>
  );
}
