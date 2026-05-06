# Agent Working Notes

- When diagnosing any bug or unexpected behavior, do a short root-cause pass before changing code: reproduce or gather evidence, inspect recent diffs, and compare against a known working example when one exists.
- For user-visible platform behavior, search the web early unless the user explicitly asks not to. Start with queries such as:
  - `Possible causes why {issue} not working`
  - `{platform} {feature} not showing in app`
  - `{framework} {control/class} {symptom}`
  - `{exact error or user-visible symptom} causes`
  - `{feature} works in some apps not others {platform}`
- Prefer primary sources for technical facts when available, then corroborate with developer reports for undocumented platform behavior.
- Keep debug probes temporary. Remove launch flags, diagnostic views, and standalone probe apps before handing work back unless the user asks to keep them.
- After code changes, build immediately. For attached-device keyboard or system UI behavior, install and launch the fresh build on the physical device; simulator-only verification is not enough.
- The project owner prefers frequent commits on `main`; commit completed changes promptly after a successful build.
