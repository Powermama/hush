# Inside hush

**[Try your first dictation](tutorials/first-dictation.md)** ·
**[Build for macOS](../macos/docs/development.md)** ·
**[Run the website](../webapp/README.md)** ·
**[Contribute](../CONTRIBUTING.md)**

## Find your way

| You want to… | Start here |
| --- | --- |
| Learn by trying hush | [Your first dictation](tutorials/first-dictation.md) |
| Build or change the app | [Native development](../macos/docs/development.md) |
| Work on the website or proof service | [Web development](../webapp/README.md) |
| Understand what stays on the Mac | [Architecture and data boundaries](explanation/architecture.md) |
| Understand which CI checks run | [Component checks and runner usage](explanation/continuous-integration.md) |
| Find expected behaviour and its tests | [User journeys](reference/user-journeys.md) |
| Diagnose a freeze | [Responsiveness checks](../macos/docs/operations/responsiveness.md) |
| Prepare a signed release | [Notarization](../macos/docs/operations/notarization.md) and [updates](../macos/docs/operations/app-updates.md) |
| Deploy the website | [Coolify deployment](../webapp/docs/operations/coolify-deployment.md) |
| Understand the repository migration | [Migration record](monorepo-migration.md) |
| Understand reuse and contribution terms | [Licensing scope](../LICENSING.md) and [assessment](../macos/docs/research/2026-11-10-open-source-licensing.md) |

## How the docs fit together

We use [Diátaxis](https://diataxis.fr/) to separate learning, completing a task,
looking up a contract and understanding a decision. It is a writing framework;
the docs remain ordinary Markdown, readable on GitHub and in a checkout.

```text
hush/
├── README.md                  # product introduction and download
├── CONTRIBUTING.md            # first contribution through pull request
├── LICENSE                    # unmodified GNU AGPLv3 text
├── LICENSING.md               # scope, retained grants and release obligations
├── CODE_OF_CONDUCT.md          # community expectations
├── SECURITY.md                # private vulnerability reporting
├── .github/                   # issue forms, PR template and CI
├── docs/
│   ├── tutorials/             # guided first steps
│   ├── explanation/           # architecture and rationale
│   ├── reference/             # journey and test navigation
│   └── research/              # dated evidence and comparisons
├── macos/
│   ├── Hush/                  # Xcode app and native tests
│   ├── Packages/              # Swift packages
│   ├── scripts/               # build and distribution tools
│   └── docs/                  # native journeys and operating guides
└── webapp/
    ├── src/                   # website and browser verifier
    ├── server/                # proof API and storage
    ├── tests/                 # browser journeys
    └── docs/                  # web journeys, design and deployment
```

Task guides stay with the component they operate on. Shared explanations and
navigation live here. Link to the owning document instead of keeping duplicate
instructions. Existing `PRD-*`, `design/` and `research/` documents explain past
decisions; they are not promises that every proposal shipped. Journey contracts
describe intended behaviour, and their test mappings identify the available
evidence and manual checks.

The [community reference review](research/2026-11-10-community-structure.md)
records the open-source projects behind this structure.
