# Desktop Buddy

**Read `SETUP.md` first.** It has the product, every feature, the architecture, setup, the release process, decisions, pending tasks and the Windows plan.

Key rules (details in SETUP.md §11):
- The owner is a UI/UX designer and not a terminal user: plain English, short replies, show results visually, run commands yourself.
- Apple-level design with the system font; good UX copy; light and dark mode.
- Every logic change gets checks in `Sources/DesktopBuddy/SelfTest.swift`; `./build-app.sh` must pass.
- Use `@Local`, not `@State` (the SwiftUI macro plugin is missing on this SDK).
- Ask before pushing, releasing, publishing the website or sharing anything.
- GitHub: `GH_TOKEN=$(gh auth token -u abhisheksaggam-design)`; never switch the default `gh` account.
- Never commit `team.json`, the signing certificate or passwords. The repo is public: no personal emails or colleagues' names, including in screenshots and tests.
- Releases: bump the version in `build-app.sh`, run `./build-app.sh --share` (signed with "Desktop Buddy Signing"), and attach `Desktop-Buddy.dmg` and `Desktop-Buddy.dmg.sha256` to a `vX.Y` GitHub release.
- Windows app: planned only (SETUP.md §13). Don't start until the owner says so.
