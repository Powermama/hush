# hush for macOS

The native app is part of the [hush monorepo](../README.md). This directory keeps
the Xcode project, speech models, Swift packages, tests and release tools together.

From the repository root:

```sh
open macos/Hush/Hush.xcodeproj
```

Use an Apple silicon Mac and Xcode 26.6. Select the **Hush** scheme and your own
signing team. The app targets macOS 15 and later.

Read the [development guide](docs/development.md) for pinned dependencies,
local setup, testing, proof-service integration and distribution. The
[repository contribution guide](../CONTRIBUTING.md) defines the shared workflow.

The project's license is **[AGPL-3.0-only](../LICENSE)**. The imported native
baseline retains its [MIT grant](LICENSE); subsequent original contributions
follow the project license. See [licensing scope](../LICENSING.md) before reusing
or distributing code, dependencies or models.
