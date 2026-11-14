import {
  Outlet,
  createRoute,
  createRootRoute,
  createRouter,
  lazyRouteComponent,
  RouterProvider,
} from "@tanstack/react-router";
import { createBlogRoutes } from "../blog/generated/routes.generated";
import { NotFoundPage } from "../not-found/NotFoundPage";

// Every page loads its own code when it is visited, as blog articles do: a
// page never downloads another page's code (the landing's scenes, proofs,
// release notes), which keeps the first load small on phones.
const rootRoute = createRootRoute({ component: () => <Outlet />, notFoundComponent: NotFoundPage });
const landingRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/",
  component: lazyRouteComponent(() => import("./App"), "App"),
});
const germanLandingRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/de",
  component: lazyRouteComponent(() => import("../landing/GermanLanding"), "GermanLanding"),
});
const proofRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/p/$slug",
  component: lazyRouteComponent(() => import("../provenance/ProofRoute"), "ProofRoute"),
});
const verifiedMessagesRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/verified-messages",
  component: lazyRouteComponent(() => import("../verified/VerifiedMessagesPage"), "VerifiedMessagesPage"),
});
const releasesRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/releases",
  component: lazyRouteComponent(() => import("../releases/ReleaseNotesPage"), "ReleaseIndexPage"),
});
const latestReleaseRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/releases/latest",
  component: lazyRouteComponent(() => import("../releases/ReleaseNotesPage"), "LatestReleasePage"),
});
const releaseRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/releases/$slug",
  component: lazyRouteComponent(() => import("../releases/ReleaseRoute"), "ReleaseRoute"),
});
const imprintRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/impressum",
  component: lazyRouteComponent(() => import("../legal/LegalPages"), "ImprintPage"),
});
const privacyPolicyRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/datenschutz",
  component: lazyRouteComponent(() => import("../legal/LegalPages"), "PrivacyPolicyPage"),
});
const germanImprintRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/de/impressum",
  component: lazyRouteComponent(() => import("../legal/LegalPages"), "GermanImprintPage"),
});
const germanPrivacyPolicyRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/de/datenschutz",
  component: lazyRouteComponent(() => import("../legal/LegalPages"), "GermanPrivacyPolicyPage"),
});
const routeTree = rootRoute.addChildren([
    landingRoute,
    germanLandingRoute,
    verifiedMessagesRoute,
    proofRoute,
    releasesRoute,
    latestReleaseRoute,
    releaseRoute,
    imprintRoute,
    privacyPolicyRoute,
    germanImprintRoute,
    germanPrivacyPolicyRoute,
    ...createBlogRoutes(rootRoute),
  ]);

export function createAppRouter() {
  return createRouter({ routeTree });
}

declare module "@tanstack/react-router" {
  interface Register {
    router: ReturnType<typeof createAppRouter>;
  }
}

export function AppRouter({ router }: { router: ReturnType<typeof createAppRouter> }) {
  return <RouterProvider router={router} />;
}
