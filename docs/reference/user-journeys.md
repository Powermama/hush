# User journeys and evidence

Start with the person and the result they should see. These documents connect
that result to its state changes, invariants and tests. They are contributor
references, not a list of marketing claims.

## Native app

| Journey | Owning contract |
| --- | --- |
| Install, grant permissions and try dictation | [Onboarding](../../macos/docs/user-journeys/onboarding.md) |
| Choose, download, cancel or remove a speech model | [Transcription models](../../macos/docs/user-journeys/transcription-models.md) |
| Choose a writing style | [Persona wheel](../../macos/docs/user-journeys/persona-wheel.md) |
| Set up the assistant, act and interrupt | [Assistant](../../macos/docs/user-journeys/hey-hush.md) |
| Control the listening interface | [HUD settings](../../macos/docs/user-journeys/hud-settings.md) |
| Measure typing with consent | [Typing benchmark](../../macos/docs/user-journeys/typing-benchmark.md) |
| Create, edit and share a signed record | [Verified Messages author](../../macos/docs/user-journeys/verified-messages.md) |
| Download and install an update | [App updates](../../macos/docs/user-journeys/app-updates.md) |

## Website and recipient

| Journey | Owning contract |
| --- | --- |
| Explore hush, navigate on mobile and reach a Mac download | [Visual landing](../../webapp/apps/web/docs/user-journeys/visual-landing.md) |
| Download the correct signed build | [Alpha download](../../webapp/apps/web/docs/user-journeys/private-alpha-download.md) |
| Understand the signed-message story | [Verified Messages landing](../../webapp/apps/web/docs/user-journeys/verified-messages-landing.md) |
| Open, decrypt and verify a private proof | [Proof recipient](../../webapp/apps/web/docs/user-journeys/proof-recipient.md) |
| Read legal and privacy information | [Legal information](../../webapp/apps/web/docs/user-journeys/legal-information.md) |
| Find public pages in search and preview shared links | [Public discovery](../../webapp/apps/web/docs/user-journeys/search-discovery.md) |
| Manage blog posts through the CMS API | [CMS journeys](../../webapp/apps/cms/docs/user-journeys/cms.md) |

## Change a journey

For a behaviour change, update the existing owning document in the same PR.
Preserve its scenario IDs. Some IDs are shared across components; identify a
scenario by its document path and ID, not the ID alone.

A new journey needs only these parts:

1. **Outcome:** what the person is trying to accomplish.
2. **Starting state and trigger:** permissions, models, focus or existing data.
3. **Observable result:** what appears, changes or remains available.
4. **Recovery:** cancellation, unavailable dependencies and failure feedback.
5. **Invariants:** the privacy, integrity or accessibility rules that must hold.
6. **Evidence:** exact automated test names, plus explicit manual checks or gaps.

Use a short Given/When/Then scenario when it improves clarity. Reproduce the
journey before fixing a bug. A unit test, fixture, compilation or mocked model
does not prove live desktop automation, permission prompts or audio-device
behaviour. Record those limits instead of marking everything as covered.

PRDs and dated research may contain superseded ideas. Update the journey and
tests to describe an intentional change; do not silently treat an old proposal
as shipped behaviour. Small text or formatting changes need proportionate
checks, not a new process document.
