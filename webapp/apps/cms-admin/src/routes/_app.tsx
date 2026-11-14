// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// The signed-in screens with navigation; the editor (_editor) has none, as in Ghost.
import { useQueryClient, useSuspenseQuery } from "@tanstack/react-query";
import { Link, Outlet, createFileRoute, useNavigate } from "@tanstack/react-router";
import { FileTextIcon, LogOutIcon } from "lucide-react";
import { requireSession } from "@/api/require-session";
import { sessionQuery, signOut } from "@/api/session";
import { HushLogo } from "@/components/hush-logo";
import {
  Sidebar, SidebarContent, SidebarFooter, SidebarGroup, SidebarHeader, SidebarInset, SidebarMenu,
  SidebarMenuButton, SidebarMenuItem, SidebarProvider, SidebarTrigger,
} from "@/components/ui/sidebar";

export const Route = createFileRoute("/_app")({
  beforeLoad: requireSession,
  component: AppLayout,
});

function AppLayout() {
  const { data: session } = useSuspenseQuery(sessionQuery);
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  return (
    <SidebarProvider>
      <Sidebar>
        <SidebarHeader className="px-4 pt-5 pb-3"><Link to="/" aria-label="hush CMS, posts"><HushLogo /></Link></SidebarHeader>
        <SidebarContent>
          <SidebarGroup>
            <SidebarMenu>
              <SidebarMenuItem>
                <SidebarMenuButton asChild>
                  <Link to="/" activeOptions={{ includeSearch: false }} activeProps={{ "data-active": true }}><FileTextIcon /><span>Posts</span></Link>
                </SidebarMenuButton>
              </SidebarMenuItem>
            </SidebarMenu>
          </SidebarGroup>
        </SidebarContent>
        <SidebarFooter className="p-3">
          <SidebarMenu>
            <SidebarMenuItem>
              <SidebarMenuButton onClick={async () => { await signOut(); queryClient.clear(); await navigate({ to: "/sign-in" }); }}>
                <LogOutIcon /><span>Sign out <span className="text-muted-foreground">({session.login})</span></span>
              </SidebarMenuButton>
            </SidebarMenuItem>
          </SidebarMenu>
        </SidebarFooter>
      </Sidebar>
      <SidebarInset>
        <div className="flex h-12 items-center px-3 md:hidden"><SidebarTrigger /></div>
        <Outlet />
      </SidebarInset>
    </SidebarProvider>
  );
}
