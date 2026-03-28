## Summary

- What changed?
- Why did it change?

## Ship Checklist

- [ ] I checked that first paint is still fast and I did not add new blocking work before initial UI render.
- [ ] I tested navigation/presentation for the changed flow and confirmed sheets, covers, and composers do not dismiss unexpectedly.
- [ ] I tested hit targets and gesture interactions for overlays, floating controls, and media actions.
- [ ] I checked both light mode and dark mode for the changed UI.
- [ ] I verified any shared setting or persisted state updates correctly across connected surfaces.
- [ ] I added or updated focused regression coverage for the changed critical path, or I am explicitly calling out why that was not possible.
- [ ] I ran the app build and manually tested the exact user flow I changed.
- [ ] I manually tested at least one adjacent flow that shares code with this change.

## Verification

- [ ] `xcodebuild -scheme Flow -project /Users/k/code/x21-ios/Flow.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

## Risks / Follow-up

- Remaining risk:
- Follow-up work:
