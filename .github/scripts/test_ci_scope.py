# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 Clemens Kressmann

from pathlib import Path
import subprocess
import tempfile
import unittest

import json

from ci_scope import classify, full_scope, scope_for_event, workspace_dependents


class ScopeTests(unittest.TestCase):
    def test_website_does_not_allocate_a_mac(self):
        for path in ["webapp/apps/web/src/landing/landing.css", "webapp/apps/web/public/art/rose.glb",
                     "webapp/apps/web/shared/legal.ts", "webapp/apps/web/shared/releases.ts",
                     "webapp/apps/web/tests/landing.spec.ts", "webapp/apps/web/vite.config.ts"]:
            with self.subTest(path=path):
                self.assertEqual(classify([path]), dict(web=True, cms=False, native=False, integration=False))

    def test_contract_and_service_changes_keep_native_integration(self):
        for path in ["webapp/apps/web/server/app.ts", "webapp/apps/web/shared/contracts/proof.ts",
                     "webapp/apps/web/shared/provenance/canonical.ts", "webapp/apps/web/openapi/hush-provenance.json",
                     "webapp/apps/web/package.json", "webapp/apps/web/tsconfig.json"]:
            with self.subTest(path=path):
                self.assertEqual(classify([path]), dict(web=True, cms=False, native=False, integration=True))

    def test_native_changes_build_and_test_without_browser_jobs(self):
        for path in ["macos/Hush/Hush/App.swift", "macos/Packages/HushProvenance/Package.resolved",
                     "macos/scripts/build-dmg.sh", "macos/Hush/Hush.xcodeproj/project.pbxproj"]:
            with self.subTest(path=path):
                self.assertEqual(classify([path]), dict(web=False, cms=False, native=True, integration=True))

    def test_documentation_does_not_start_product_builds(self):
        paths = ["README.md", "LICENSE", "macos/LICENSE", "macos/docs/settings.png",
                 "docs/explanation/ci.md", "webapp/apps/web/docs/user-journeys/legal-information.md",
                 ".github/ISSUE_TEMPLATE/bug.yml"]
        self.assertEqual(classify(paths), dict(web=False, cms=False, native=False, integration=False))

    def test_cms_changes_run_only_the_cms(self):
        for path in ["webapp/apps/cms/src/app.ts", "webapp/apps/cms/Dockerfile",
                     "webapp/apps/cms/src/db/migrations/0000_initial.sql"]:
            with self.subTest(path=path):
                self.assertEqual(classify([path]), dict(web=False, cms=True, native=False, integration=False))

    def test_shared_packages_run_the_apps_that_depend_on_them(self):
        dependents = {"article": {"web", "cms"}, "ui": {"cms"}}
        self.assertEqual(classify(["webapp/packages/article/src/article.ts"], dependents),
                         dict(web=True, cms=True, native=False, integration=False))
        self.assertEqual(classify(["webapp/packages/ui/src/button.tsx"], dependents),
                         dict(web=False, cms=True, native=False, integration=False))

    def test_workspace_root_files_run_every_web_app(self):
        for path in ["webapp/package.json", "webapp/bun.lock", "webapp/.dockerignore", "webapp/compose.yaml"]:
            with self.subTest(path=path):
                self.assertEqual(classify([path]), dict(web=True, cms=True, native=False, integration=True))

    def test_unknown_apps_and_packages_run_everything(self):
        self.assertEqual(classify(["webapp/apps/new-app/src/index.ts"]), full_scope())
        self.assertEqual(classify(["webapp/packages/new-package/index.ts"], {}), full_scope())

    def test_dependents_come_from_the_workspace_manifests(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifests = {
                "apps/web": {"name": "@x/web", "dependencies": {"@x/article": "workspace:*"}},
                "apps/cms": {"name": "@x/cms", "dependencies": {"@x/editor": "workspace:*"}},
                "packages/article": {"name": "@x/article"},
                "packages/editor": {"name": "@x/editor", "dependencies": {"@x/article": "workspace:*"}},
            }
            for folder, manifest in manifests.items():
                (root / "webapp" / folder).mkdir(parents=True)
                (root / "webapp" / folder / "package.json").write_text(json.dumps(manifest))
            self.assertEqual(workspace_dependents(root), {"article": {"web", "cms"}, "editor": {"cms"}})

    def test_mixed_changes_run_both_components(self):
        self.assertEqual(classify(["macos/Hush/App.swift", "webapp/apps/web/src/main.tsx"]),
                         dict(web=True, cms=False, native=True, integration=True))

    def test_workflow_or_unknown_configuration_runs_everything(self):
        for path in [".github/workflows/ci.yml", ".github/scripts/ci_scope.py",
                     ".github/dependabot.yml", "future-component/main.rs", "Makefile"]:
            with self.subTest(path=path):
                self.assertEqual(classify([path]), full_scope())

    def test_manual_initial_and_invalid_comparisons_run_everything(self):
        for name, event in [("workflow_dispatch", {}), ("merge_group", {}),
                            ("push", {"before": "0" * 40, "after": "a" * 40}),
                            ("pull_request", {}),
                            ("push", {"before": "--output=oops", "after": "a" * 40})]:
            with self.subTest(name=name, event=event):
                self.assertEqual(scope_for_event(name, event)[0], full_scope())


class GitJourneyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "CI fixture")
        self.git("config", "user.email", "ci@example.invalid")
        self.commit("webapp/apps/web/src/main.tsx", "initial")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], stderr=subprocess.PIPE).decode().strip()

    def commit(self, path, content):
        file = self.repo / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)
        self.git("add", ".")
        self.git("commit", "-m", "fixture")
        return self.git("rev-parse", "HEAD")

    def test_push_includes_all_commits_in_the_push(self):
        base = self.git("rev-parse", "HEAD")
        self.commit("macos/Hush/App.swift", "native")
        head = self.commit("README.md", "docs")
        scope, _ = scope_for_event("push", dict(before=base, after=head), self.repo)
        self.assertEqual(scope, dict(web=False, cms=False, native=True, integration=True))

    def test_pr_uses_merge_base_not_unrelated_base_branch_changes(self):
        self.git("checkout", "-b", "feature")
        head = self.commit("webapp/apps/web/src/main.tsx", "new website")
        self.git("checkout", "main")
        base = self.commit("macos/Hush/App.swift", "unrelated native change")
        event = {"pull_request": {"base": {"sha": base}, "head": {"sha": head}}}
        scope, _ = scope_for_event("pull_request", event, self.repo)
        self.assertEqual(scope, dict(web=True, cms=False, native=False, integration=False))

    def test_rename_out_of_component_still_checks_deleted_source(self):
        base = self.git("rev-parse", "HEAD")
        self.git("mv", "webapp/apps/web/src/main.tsx", "example.md")
        self.git("commit", "-m", "rename")
        head = self.git("rev-parse", "HEAD")
        scope, _ = scope_for_event("push", dict(before=base, after=head), self.repo)
        self.assertEqual(scope, dict(web=True, cms=False, native=False, integration=False))

    def test_rewritten_or_missing_base_runs_everything(self):
        scope, _ = scope_for_event("push", dict(before="a" * 40, after=self.git("rev-parse", "HEAD")), self.repo)
        self.assertEqual(scope, full_scope())


if __name__ == "__main__":
    unittest.main()
