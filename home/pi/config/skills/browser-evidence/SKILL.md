---
name: browser-evidence
description: Use when a web application, generated report or authenticated browser journey needs actual UI, console/network and artifact acceptance rather than source-only review.
---
# Browser acceptance evidence

- Use `agent_browser` for real browsing and browser automation. Read the current tool contract. Define the intended app/interface, exact success/failure journey and artifact obligations in the accepted ledger before running them; see [workflow semantics](../../extensions/auto-mode/WORKFLOW.md).
- Start with an isolated or explicitly approved named/profile session. Verify the actual URL and authentication state. Use a fresh session for launch-only flags. Never copy an arbitrary browser profile or bypass an explicit stop, authentication requirement or protected-action gate.
- Follow open → snapshot → interaction using current references or stable semantic locators. Re-snapshot after navigation/state changes. Inspect omitted high-value controls and verify scrolling in dense dashboards.
- Exercise what a user does: clean-start the authorized app/dependencies where needed, perform the actual create/forge/edit/export path, test a relevant failure, and inspect console errors and failed network requests. Source readers, mocked pages, successful clicks and timeouts alone are not acceptance.
- For Berrit/product deliverables, check the full requested report/presentation/slides/video checklist. Generate and open the final single-file report itself; verify its important content and interactions rather than only testing the generator.
- Save artifacts to exact authorized paths outside source roots. Inspect screenshots/downloaded content and the tool's artifact-verification fields before claiming success. Preserve files required by prompt guards before closing. Do not overwrite source with downloads/screenshots.
- Avoid cross-child interference: one owner per browser session, no concurrent interactions with the same page/profile. Clean up only owned sessions/processes and retain the evidence needed by the parent.
- Do not expose cookies, tokens or private form contents in reports. Purchases, irreversible submissions, account/security/privacy changes and production controls need explicit authorization.
- Attach real finalized tool-call IDs and required artifact fingerprints to acceptance. Report environment/auth limitations and distinguish tested local fixtures from the actual deployed app.
