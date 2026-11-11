import {
  Outlet,
  createRoute,
  createRootRoute,
  createRouter,
  RouterProvider,
  useParams,
} from "@tanstack/react-router";
import { App } from "./App";
import { ProofPage } from "../provenance/ProofPage";
import {
  LatestReleasePage,
  MissingReleasePage,
  ReleaseDetailPage,
  ReleaseIndexPage,
} from "../releases/ReleaseNotesPage";
import { findRelease } from "../../shared/releases";
import { ImprintPage, PrivacyPolicyPage } from "../legal/LegalPages";
import { VerifiedMessagesPage } from "../verified/VerifiedMessagesPage";

const rootRoute = createRootRoute({ component: () => <Outlet /> });
const landingRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/",
  component: App,
});
const proofRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/p/$slug",
  component: ProofRoute,
});
const verifiedMessagesRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/verified-messages",
  component: VerifiedMessagesPage,
});
const releasesRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/releases",
  component: ReleaseIndexPage,
});
const latestReleaseRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/releases/latest",
  component: LatestReleasePage,
});
const releaseRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/releases/$slug",
  component: ReleaseRoute,
});
const imprintRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/impressum",
  component: ImprintPage,
});
const privacyPolicyRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/datenschutz",
  component: PrivacyPolicyPage,
});
const germanImprintRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/de/impressum",
  component: () => <ImprintPage language="de" />,
});
const germanPrivacyPolicyRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/de/datenschutz",
  component: () => <PrivacyPolicyPage language="de" />,
});
const routeTree = rootRoute.addChildren([
    landingRoute,
    verifiedMessagesRoute,
    proofRoute,
    releasesRoute,
    latestReleaseRoute,
    releaseRoute,
    imprintRoute,
    privacyPolicyRoute,
    germanImprintRoute,
    germanPrivacyPolicyRoute,
  ]);

export function createAppRouter() {
  return createRouter({ routeTree });
}

function ProofRoute() {
  const { slug } = useParams({ from: "/p/$slug" });
  return <ProofPage slug={slug} />;
}

function ReleaseRoute() {
  const { slug } = useParams({ from: "/releases/$slug" });
  const release = findRelease(slug);
  return release ? (
    <ReleaseDetailPage release={release} />
  ) : (
    <MissingReleasePage />
  );
}

declare module "@tanstack/react-router" {
  interface Register {
    router: ReturnType<typeof createAppRouter>;
  }
}

export function AppRouter({ router }: { router: ReturnType<typeof createAppRouter> }) {
  return <RouterProvider router={router} />;
}
