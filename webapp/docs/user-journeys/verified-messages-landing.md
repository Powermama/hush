# Verified Messages landing journey

## Goal

A visitor understands that a Verified Message is an optional, encrypted record of how a message was captured, edited and signed. A recipient verifies that record in a browser. This does not establish identity, truth or liveness.

## Trust invariants

- Verification is optional.
- The proof package is encrypted on the Mac before upload.
- The key stays in the complete private link and is not sent to the hush service.
- Anyone with that complete link can read the proof while available.
- Original audio is not uploaded with the proof.
- Recipients check the signed record in a browser without an account.
- Recorded times do not establish an independent timestamp or human presence.
- Every marketing proof is labelled illustrative and does not run real verification.
- Capture, manual changes and local AI refinement are distinct. The example follows one voice-origin message, not all supported origins.
- Never imply proof of identity, accuracy, liveness or guaranteed freedom from AI.
- No referral rewards, growth streaks or social pressure encourage publication.

## Scenarios

### LANDING-VM-001 - Understand optional verification

Follow “Explore Verified Messages” from the home page. The dedicated page explains local capture, visible edits, a shared message, a recipient mock-up, browser decryption, message-key privacy and verification limits. The download retains its immutable release URL.

### LANDING-VM-002 - Follow the closing provenance chapter

After the local-intelligence composition, a printing-press collage connects publishing to uncertain digital origins. “Reality has a copy problem.” resolves into the smaller “Give your words their story back.” headline and a single “Discover Verified Messages” link. There is no extra explanation grid or “What’s verified?” dropdown. The full optionality and proof boundaries live on the dedicated page. The woodcut remains locally hosted and credited.

### LANDING-VM-003 - Follow one message into a social post

The robot opening leads to one artistic composition over Klee's mechanical birds. A single window shows local voice capture, a social post, and the recipient's signed history. One 15-second sequence replaces the three long explanatory chapters. The original transcript and final message remain consistent; the proof records the manual addition of “together”.

The page shares the landing page's light header, deep blue typography and continuous pale blue/lilac canvas. The fragmented robot, Klee artwork and final invitation flow together without alternating dark section backgrounds. On desktop the larger opening headline sits beside the sculpture, and the message window sits below the story heading in front of the artwork. On mobile the same reading order stacks without overlapping text, controls or credits. The final dark download retains its colours on hover and a visible keyboard focus outline.

This treatment adds no WebGL context, external asset or continuous animation. The existing portrait renders only when needed; the finite story, reduced-motion mode, WebGL fallback, mobile download handoff and signed-history boundaries stay intact.

The post uses familiar social typography, author details, metadata and engagement icons. Its “- verified by hush” link is part of the message body, in the same paragraph and type size with no blank line, before the post timestamp and engagement footer. Activating it opens the illustrative proof and moves keyboard focus there. The proof shows three UTC events without a recorded-edit disclosure. There is no “About this illustration & your privacy” dropdown.

A short visible line explains that audio stays on the Mac and only text and signed history travel encrypted. The persistent Illustration label distinguishes the mockup from a real verification result. The detailed privacy policy remains in the footer. Source and license links stay with each artwork. No external image requests, horizontal scrolling or console errors occur. No home-page imagery or political portrait is reused. The final download and optionality note remain.

### LANDING-VM-004 - Read without WebGL or motion

With reduced motion and unavailable WebGL, the static robot remains and the story starts on a static proof. Record, Share and Verify controls allow direct selection without animation. Keyboard users can skip the header, follow the post signature and read the three-event chronology. No microphone access or real publishing occurs.

### LANDING-VM-005 - Control the illustration

The sequence plays once when its window enters view, reaches the social post after five seconds, the proof after ten seconds, and stops after fifteen seconds. It pauses offscreen and when the document is hidden. Pause, resume and replay are explicit controls; selecting a stage or focusing interactive content pauses playback. No automatic loop or idle animation runs after completion. Reduced motion uses static stage controls instead of playback.

## Test mapping

| Journey | Automated evidence |
| --- | --- |
| LANDING-VM-001 | tests/landing.spec.ts follows the home link and checks metadata, the recipient example, local audio, encrypted sharing and proof limits. |
| LANDING-VM-002 | tests/landing.spec.ts checks home chapter order, artwork/credit, readable titles and keyboard navigation. |
| LANDING-VM-003 | tests/verified-story.spec.ts selects each stage, checks the inline signature and keyboard focus, checks the visible chronology and captures desktop/mobile/WebKit compositions. |
| LANDING-VM-004 | tests/verified-story.spec.ts disables WebGL, requests reduced motion and exercises keyboard navigation and the static story. |
| LANDING-VM-005 | tests/verified-story.spec.ts exercises the real timed sequence, offscreen pause, manual pause, resume and replay. |
