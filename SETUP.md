# Desktop Buddy: setup and handover guide

This one file holds everything about Desktop Buddy: what it is, every feature, how it's built, how to set it up and release it, the decisions made so far and why, what's still pending, and the plan for the Windows app.

**If you are an AI agent picking this project up, read this whole file first.** Then follow the house rules in [§11](#11-how-to-work-on-this-project-house-rules).

| | |
|---|---|
| Product | Desktop Buddy: read-only desktop notifications for Google Workspace and Microsoft 365 |
| Platforms | macOS (shipping, version **2.4**). Windows (planned, [§13](#13-windows-app-plan)) |
| Repository | `github.com/abhisheksaggam-design/desktop-buddy` (public) |
| Owner | Dynamatix |
| Latest release | `v2.4` on GitHub Releases (`Desktop-Buddy.dmg` + `Desktop-Buddy.dmg.sha256`) |
| Last updated | 10 November 2026 |

---

## Contents

1. [What Desktop Buddy is](#1-what-desktop-buddy-is)
2. [Feature list (macOS 2.4)](#2-feature-list-macos-24)
3. [How it works (architecture)](#3-how-it-works-architecture)
4. [Privacy and security rules](#4-privacy-and-security-rules)
5. [Accounts, services and where things live](#5-accounts-services-and-where-things-live)
6. [Setting up a Mac to build Desktop Buddy](#6-setting-up-a-mac-to-build-desktop-buddy)
7. [Google, Microsoft and team.json setup](#7-google-microsoft-and-teamjson-setup)
8. [Building, testing and releasing](#8-building-testing-and-releasing)
9. [Release history](#9-release-history)
10. [The AI agents](#10-the-ai-agents)
11. [How to work on this project (house rules)](#11-how-to-work-on-this-project-house-rules)
12. [Pending tasks](#12-pending-tasks)
13. [Windows app plan](#13-windows-app-plan)
14. [Decisions and why (context board)](#14-decisions-and-why-context-board)
15. [Repository map](#15-repository-map)

---

## 1. What Desktop Buddy is

Desktop Buddy is a small menu bar app. It shows a calm notification on the desktop when something needs attention in any of a person's work accounts:

- new unread email (Gmail, Outlook)
- new chat messages (Google Chat, Teams chats)
- meetings starting soon (Google Calendar with Meet links, Outlook Calendar with Teams links)
- tasks due today (Google Tasks, Microsoft To Do)
- personal reminders, for example "drink water every 30 minutes" (work offline)

It's built for people who work across several workspaces (Dynamatix, IE Hub and client tenants) and miss messages spread over many browser tabs.

**What makes it different:** **Clients**. Mail and chats from a client (by sender domain, keyword or picked chat) are grouped under that client's logo, even when the client never gave you an account.

**Promises the app keeps:**
- **Read-only.** It never sends, changes or deletes anything.
- **No servers of ours.** The Mac talks directly to Google and Microsoft.
- **No analytics. No AI.**
- **Everything stays on the Mac.** The exceptions are the GitHub update check, and bug reports that the person chooses to send ([§4](#4-privacy-and-security-rules)).

---

## 2. Feature list (macOS 2.4)

### Accounts and sign-in
- **Sign in first.** Settings opens with **Sign in with Google** and **Sign in with Microsoft**. The browser opens, the person picks their account, clicks Allow, and that's it.
- **Automatic naming.** The email is filled in, and the account is named from its domain: `you@dynamatix.co.uk` becomes **Dynamatix**, `@iehub.org` becomes **IE Hub**, `@acme-ltd.com` becomes **Acme Ltd**, and personal Gmail or Outlook addresses become **Personal**. If a name is already taken, a number is added ("Dynamatix 2"). The person can rename the account on the last screen.
- **One sign-in covers everything:** mail, chats, meetings and tasks. Each one has an on/off switch per account.
- **Duplicates are blocked** with a message.
- **Account status:** Connected, Not Signed In, Sign-in Expired (with Sign In Again), or Signed In as a Different Account.
- **If sign-in isn't built into a copy:** the sheet explains it and offers **Import Setup File…**. There are no developer fields.

### Notifications on screen
- **Dock of logos:** one logo per client or account, plus reminders, each with a red count badge. The dock can sit in a corner, along the bottom, or up a side. Drag it from any place to any other: the place nearest the pointer wins. Logos keep their place when new items arrive; new logos join on the left and fade in.
- **Menu bar pop-up ("island"):** a small black island drops from the top centre with who the item is from and what it says, then tucks away after 10 seconds. Hovering pauses it, clicking opens the item, and **View more** opens the list.
- **Notification list,** styled like Notification Center: grouped by client or account, with a filter bar of logos, Clear per group, and Clear All. Hovering a card gives ✕ (done) and a snooze menu (10 minutes, 1 hour, tomorrow 9 am). Right-click gives more options. **Esc** closes the list.
- **Undo** for 6 seconds after Clear All, Clear or Done, using the button or ⌘Z.
- **Menu bar dropdown:**
  - the Desktop Buddy mark with a count
  - an account strip with quick on/off switches
  - rows that match the on-screen list
  - a ••• menu with Quit, Check for Updates and "Allow Screenshots for 1 Minute"
  - right-click options on rows
- **Screen-share privacy:** "Hide from Screen Sharing" keeps the logos and pop-up out of screen shares. macOS uses the same switch for screenshots, so "Allow Screenshots for 1 Minute" turns it off briefly.
- **Sounds:** a different sound per notification type, with a preview button.
- **Quiet hours and Pause:** nothing pops up while they're on; items wait in the list.
- **Logo names** update as soon as an account or client is renamed.

### Mail filters and muting (per account)
- **"Only mail with chosen labels":** Gmail labels or Outlook categories, from any folder. Without it, the app watches unread inbox mail from the last 2 days.
- **Mute:** senders, keywords and chats that never notify.

### Clients
- **Rules:**
  - **Senders:** an exact address, a domain or a subdomain
  - **Keywords:** whole word, case-insensitive ("Hub" doesn't match "GitHub")
  - **Picked chats:** Google Chat spaces or Teams chats
  - **Name match:** chats whose name contains the client's name
  - **Look in:** all accounts, or chosen ones
- **Needs Attention** flags any rule that can't work, with a one-click fix. Examples: the client is off, the account or service is off, the sign-in has expired, a chat is outside Look in, there are no rules, or a keyword is too common (like "team").
- **Built-in logos:** Dynamatix (brown tree, also the app icon), IE Hub (green "IE" octagon), RiskHawk (globe), Gatehouse (green and blue "G" hexagon). People can choose any image as a logo.

### Settings (System Settings style)
- **Sections:** Accounts, Clients, General, Appearance (logos and size), Reminders, Team Setup.
- **Admin-only:** client IDs are hidden unless the Option key is held.
- **General → Updates:** shows the version, has a Check Now button, and a switch for automatic checks.

### Updates
- **Once a day,** and on demand, the app asks GitHub for the latest release. A newer version shows a banner with **Update and Restart**.
- **Before installing,** the app downloads `Desktop-Buddy.dmg` and checks it against the release's `.sha256` file. It also checks the app inside is signed with the **Desktop Buddy Signing** certificate. Then it swaps the app in place and reopens it. Anything unexpected stops the update.

### Help and feedback
- **Welcome / what's-new tour,** shown once.
- **Report a Bug or an Idea:** the report is sent through Formspree when `feedbackFormID` is set in `team.json`. Otherwise it opens a Mail draft. **Not configured yet** ([§12](#12-pending-tasks)).

### Quality
- **Built-in self-test** (`--selftest`): **231 checks**. They cover client rules, the inbox lifecycle, switches, client health, reminders, quiet hours, parsing, the Keychain store, sign-in (loopback and app link), account naming, version comparison, dock placement, screen sharing, undo and more. Every build runs them, and a failure stops packaging.

---

## 3. How it works (architecture)

- **Native Swift app:** Swift 6, SwiftUI hosted in AppKit, Swift Package Manager, macOS 14+. **No third-party libraries.**
- **No backend:** polling, rule matching and storage all run inside the app on the Mac.
- **Polling:** every 60 seconds (configurable, minimum 30) for each enabled, signed-in account. The steps are fetch, then normalise, then match client rules, then reconcile (remove items read or deleted elsewhere), then show.
- **Sign-in:** OAuth 2.0 for native apps (RFC 8252) with PKCE (S256) in the system browser.
  - **Google:** an **iOS-type client with no secret**. Google returns to the app's own link, `com.googleusercontent.apps.<client-id>:/oauth2redirect`. The build registers it in `Info.plist` when `team.json` has a Google client with no secret.
  - **Microsoft:** a public client with a one-time loopback listener on `http://localhost:<port>`.
- **Google scopes (all read-only):** `openid email gmail.readonly calendar.readonly chat.spaces.readonly chat.messages.readonly tasks.readonly directory.readonly`
- **Microsoft delegated permissions:** `openid email offline_access User.Read Mail.Read Calendars.Read Chat.Read Tasks.Read`
- **Identity on disk:** bundle ID `com.desktopbuddy.v2`, executable `DesktopBuddyV2`, data folder `~/Library/Application Support/DesktopBuddyV2/`, Keychain service `com.desktopbuddy.v2`. These still say "v2" internally so existing sign-ins carry over; users only ever see "Desktop Buddy".

APIs used: Gmail, Google Chat, Google Calendar, Google Tasks, People, OpenID userinfo, and Microsoft Graph v1.0 (`/me/mailFolders/inbox/messages`, `/me/chats`, `/me/calendarView`, `/me/todo/...`, `/me`). The full endpoint list is in the technical specification ([§5](#5-accounts-services-and-where-things-live)).

---

## 4. Privacy and security rules

Every change must keep these true, or the technical spec and README must say exactly what changed.

| Area | Rule |
|---|---|
| Permissions | Read-only scopes and delegated permissions only |
| Tokens | Refresh tokens only in the macOS Keychain. Access tokens in memory only. |
| Local data | Settings and the notifications on screen (sender, subject, short preview, link). No email bodies or attachments. |
| Log | `status.log`: counts and errors only, never content or tokens. Capped at 1 MB plus one old file. |
| Network | Google and Microsoft APIs. Once a day, `api.github.com` for the update check (no user data). When the person sends a bug report: Formspree (only what they typed, plus app and macOS version). |
| Dependencies | None. Apple frameworks only. |
| Secrets in the repo | **Never.** `team.json`, the signing certificate and its password are never committed. |

---

## 5. Accounts, services and where things live

| What | Where | Notes |
|---|---|---|
| Code | GitHub `abhisheksaggam-design/desktop-buddy` (public) | Push with the `abhisheksaggam-design` account ([§11](#11-how-to-work-on-this-project-house-rules)) |
| Local project | `~/Documents/Desktop Buddy` on the owner's Mac | |
| Google Cloud project | Project number **179170437955** | Google Auth Platform: External, **In production, unverified** (100-user limit, "unverified app" warning). APIs enabled: Gmail, Calendar, Chat, Tasks, People. Chat app configured. |
| Google OAuth client | iOS type, bundle ID `com.desktopbuddy.v2`, client ID `179170437955-jd5kkla08uou3rk9pp17jdargau5it0d.apps.googleusercontent.com` | Public by design, no secret. Team ID and App Check left empty. |
| Microsoft Entra app | **Not created yet** | See [§12](#12-pending-tasks) |
| `team.json` | Project folder, git-ignored | Currently `{"googleClientID": "…"}` |
| Signing certificate | "Desktop Buddy Signing" in the build Mac's login keychain. Backup `~/Documents/Desktop Buddy Signing/signing.p12`, password in `p12-password.txt` next to it. | **Keep a copy in a password manager.** See `docs/signing.md`. |
| Technical specification | Google Doc "Desktop Buddy – Technical Specification" in the owner's Dynamatix Drive, shared with the reviewer as a commenter | For the company's security and IT review. Last updated for 2.1 ([§12](#12-pending-tasks)). |
| Website | `site/` (Next.js, static export) | Built, **not published** |
| Agents | `.claude/agents/` | [§10](#10-the-ai-agents) |

---

## 6. Setting up a Mac to build Desktop Buddy

1. Install the Xcode Command Line Tools: `xcode-select --install`. Full Xcode isn't needed.
2. Clone the repo: `gh repo clone abhisheksaggam-design/desktop-buddy`.
3. Put `team.json` in the project folder. It's git-ignored; get it from the owner, or make it as in [§7](#7-google-microsoft-and-teamjson-setup).
4. Import the signing certificate so releases are signed with the team identity (password in `p12-password.txt`):
   `security import signing.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign`
5. Run `./build-app.sh --install`. It builds, runs the self-test, installs to /Applications and opens the app.
6. **The DMG design tool** (`dmgbuild`) is set up automatically in `.tools/` the first time you run `./build-app.sh --share`. That needs internet once.
7. **Website:** run `npm --prefix site install` once, then `npm --prefix site run dev` (port 3100). `.claude/launch.json` has a "site" preview entry.

**Known toolchain quirk:** on this macOS SDK, SwiftUI's `@State` macro plugin is missing. The code uses a custom `@Local` property wrapper (`LocalState.swift`) instead. Don't use `@State`.

---

## 7. Google, Microsoft and team.json setup

The README has the full click-by-click steps (sections 2–4). In short:

**Google (done):**
1. Create the project and enable 5 APIs. One link does it all: `https://console.cloud.google.com/flows/enableapi?apiid=gmail.googleapis.com,calendar-json.googleapis.com,chat.googleapis.com,tasks.googleapis.com,people.googleapis.com`
2. Google Chat API → Configuration: set an app name and avatar. Chat won't work without this.
3. Google Auth Platform → Branding: app name **Desktop Buddy**, support email. Home page and privacy policy links can use the company website.
4. Audience: External, **Publish app** (In production). Without this, only listed test users can sign in, and sign-ins expire every 7 days.
5. Data Access: add the 8 scopes from [§3](#3-how-it-works-architecture).
6. Clients → Create → **iOS**, bundle ID `com.desktopbuddy.v2`.

**Client workspaces (per client):** their Google admin can trust the app. They go to Admin console → Security → API controls → App access control, add the client ID, and set it to **Trusted**. Their users then see no warning.

**Microsoft (to do):**
1. Entra admin center → App registrations → New: multi-tenant.
2. Add the **Mobile and desktop** platform with redirect `http://localhost`, and turn on **Allow public client flows**. No secret.
3. Add the delegated Graph permissions from [§3](#3-how-it-works-architecture).
4. Put `"microsoftClientID": "<id>", "microsoftTenant": "organizations"` in `team.json`.

**`team.json` keys:**

```json
{
  "googleClientID": "….apps.googleusercontent.com",
  "googleClientSecret": "only for a Desktop-type Google client; leave out for iOS type",
  "microsoftClientID": "00000000-…",
  "microsoftTenant": "organizations",
  "feedbackFormID": "Formspree form ID, for Report a Bug",
  "feedbackEmail": "fallback address for Report a Bug"
}
```

`team.json` is **built into the app** at build time. With an iOS-type Google client it holds only public IDs. Never commit it.

---

## 8. Building, testing and releasing

```bash
./build-app.sh            # build + self-test
./build-app.sh --install  # also install to /Applications and open
./build-app.sh --share    # also make dist/Desktop-Buddy.dmg (designed window) + .sha256
```

**The DMG install window** (`dmg/`): a tiny Mac desktop with Desktop Buddy's menu bar. The app's black pop-up says *"Drag me into Applications. I'll keep an eye on things."*, and a dotted path of mail, chat and meeting bubbles leads from the app to Applications. The background is slate blue so Finder's file names stay readable in light and dark mode. Regenerate it with `python3 dmg/make-background.py` (needs Pillow). The layout is in `dmg/settings.py`.

**Release checklist:**
1. Raise `CFBundleShortVersionString` (for example 2.4 → 2.5) and `CFBundleVersion` (+1) in `build-app.sh`, and `version` in `site/lib/site.ts`.
2. Make sure `team.json` is in the folder and the signing certificate is in the keychain. The build should print "Signed with Desktop Buddy Signing".
3. `./build-app.sh --share`. All self-test checks must pass.
4. Commit and push `main` with the `abhisheksaggam-design` account.
5. Create GitHub release `v2.5` and attach **both** `dist/Desktop-Buddy.dmg` and `dist/Desktop-Buddy.dmg.sha256`. The in-app updater needs exactly these names.
6. Within a day, everyone's app offers **Update and Restart**.

Never ship an ad-hoc-signed build to users. The updater rejects it, and the Keychain would ask everyone again.

---

## 9. Release history

| Version | Date | What changed |
|---|---|---|
| 2.0 | 26 Oct 2026 | Sign in first, account named from the email, Google sign-in built in |
| 2.1 | 26 Oct 2026 | Daily update check (banner, Settings, menu) |
| 2.2 | 27 Oct 2026 | Mail filters and labels, mute rules, sounds, clearer dropdown, welcome tour, screen-share privacy |
| 2.3 | 27 Oct 2026 | Update and Restart (checksum and signature verified), stable team signing |
| 2.4 | 10 Nov 2026 | On-screen dock (any corner or edge, drag anywhere), menu bar pop-up, Report a Bug, Undo, matching dropdown rows, Esc closes the list, mute chats per account, logos stay put, designed DMG install window |

**Before 2.0** (the original app, now retired): the same core app with a type-your-email Add Account form, a Desktop-type Google client with a secret, and bundle ID `com.desktopbuddy.app`.

---

## 10. The AI agents

The agents are defined in `.claude/agents/`. Claude Code picks them up automatically when this folder is opened, on any account.

| Agent | Job | Open it with |
|---|---|---|
| `website-builder` | The Desktop Buddy website in `site/`: home page, privacy policy, get-started page. Apple-quality design and plain English. Asks before publishing. | `@website-builder …` in a chat in this project, or `claude --agent website-builder` |
| `feature-builder` | Adds the owner's features to the **Mac app**. Doesn't work on other platforms unless asked. | `@feature-builder …`, or `claude --agent feature-builder` |
| `windows-builder` | The Windows app ([§13](#13-windows-app-plan)). **Waits for the owner to say "start Windows"** before writing code. | `@windows-builder …`, or `claude --agent windows-builder` |

In the Claude desktop app, start a new chat in this project folder and begin with `@feature-builder` (or another agent). Each agent works in its own chat.

---

## 11. How to work on this project (house rules)

These are how the work has been done so far. Keep doing it this way.

**The owner:**
- The owner is a **UI/UX designer** and is **not familiar with the terminal**.
- Explain things in **plain, simple English**, keep replies short, and show results visually (screenshots of the app or site).
- Run commands yourself. Don't ask the owner to.

**Design:**
- Apple-level design: the Human Interface Guidelines and the System Settings style.
- System font (SF Pro): never rounded or heavy, no "AI slop" looks.
- No slide-in/out animations, no divider lines or borders where avoidable.
- Light and dark mode, with readable contrast.

**Copy:** plain English, short sentences, sentence case, good UX copy. Example: "Sign-in isn't set up in this copy yet", not jargon.

**Testing:**
- Every logic change gets self-test checks in `SelfTest.swift`. `./build-app.sh` must pass.
- Test what you build before reporting, using `--snapshot <dir>` to render screens offscreen.
- Say plainly what you couldn't test.

**Ask first** before anything outward-facing:
- pushing, releases, making the repo public or private
- publishing the website
- sharing documents or sending messages

**GitHub:**
- Use the `abhisheksaggam-design` account like this: `GH_TOKEN=$(gh auth token -u abhisheksaggam-design) gh …`
- For `git push`, pass the token as an HTTP header for that one command.
- **Never switch the default `gh` account.**

**Secrets:**
- Never commit `team.json`, `signing.p12` or passwords.
- Scan before every push: `git grep --cached -nE "GOCSPX-[A-Za-z0-9_-]{10,}"`.
- Keep personal emails and colleagues' names out of this public repo, including screenshots and tests. Use sample data.

**Google Docs and Drive (the spec):** the owner works with two Google accounts (Dynamatix and IE Hub) through local Google Workspace tools. Use the Dynamatix account for the spec, and never mix the two.

**Version numbers:** the app version is the release tag. Don't announce a "new version" for documentation-only changes.

---

## 12. Pending tasks

Highest priority first.

| # | Task | Notes |
|---|---|---|
| 1 | **Update the technical specification for 2.2–2.4** | It describes 2.1. It needs: **Update and Restart** (the app now installs a verified update itself, so "never installs by itself" is no longer true); **Report a Bug via Formspree** (a new third-party flow, only when the person sends it); the **Gmail labels option** (reads labelled mail from any folder, not only the inbox); screen-share privacy; the dock and menu bar pop-up; the team signing certificate. Also replace Figure 6 (General settings). Then tell the reviewer. |
| 2 | **Set up Microsoft 365 sign-in** | Create the Entra app ([§7](#7-google-microsoft-and-teamjson-setup)), add `microsoftClientID` to `team.json`, release, and test with a real tenant. It has never been tested live. |
| 3 | **Publish the website** | `site/` is built (desktop-style home page, get-started, privacy). Choose GitHub Pages or the company website, then add its home and privacy links on the Google Branding page. |
| 4 | **Set up Report a Bug** | Create a Formspree form and put `feedbackFormID` (and `feedbackEmail`) in `team.json`. Until then it opens a Mail draft. |
| 5 | **Google verification** (optional) | Needed only to go past 100 users with no warning. Restricted scopes (Gmail, Chat) need a paid yearly CASA security assessment. Meanwhile, client domains can mark the app Trusted. |
| 6 | **Apple Developer ID + notarisation** (optional, $99/year) | Removes the first-time "Open Anyway" step. Sign and notarise with `SIGN_ID=…` and `notarytool` (README §9). |
| 7 | **Windows app** | Planned in [§13](#13-windows-app-plan). Don't start until the owner says so. |
| 8 | Ideas from earlier | "Check Services" diagnostic (granted scopes plus a probe of each API); keywords for chat text and meeting titles; `chat.memberships.readonly` to name DMs that have no messages yet; optional App Sandbox build. |

---

## 13. Windows app plan

**Status: planned, not started.** Don't build until the owner says "start Windows". The `windows-builder` agent follows this plan.

### Goal
The same product on Windows 10/11: the same features, rules, privacy promises and sign-in-first flow as macOS 2.4, designed natively for Windows 11 (Fluent).

### Recommended technology
- **WinUI 3 (Windows App SDK) with .NET 8 and C#.** That gives a true Windows 11 look: Mica material, Segoe UI Variable, light and dark mode.
- **No third-party libraries**, matching macOS. The tray icon uses Win32 `Shell_NotifyIcon` through P/Invoke, and HTTP uses `HttpClient`.
- Code in a `windows/` folder in this same repo.

### How macOS pieces map to Windows

| macOS | Windows |
|---|---|
| Menu bar icon and dropdown | System tray (notification area) icon and flyout |
| On-screen dock of logos, menu bar pop-up | Borderless, always-on-top, click-through transparent windows near a screen corner. The pop-up drops from the top centre. Exclude them from screen capture with `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`. |
| Keychain | Windows Credential Manager (`CredWrite` / `CredRead`), or DPAPI-encrypted files |
| `~/Library/Application Support/DesktopBuddyV2/` | `%LOCALAPPDATA%\DesktopBuddy\` |
| Launch at login (SMAppService) | Startup task (MSIX) or the `HKCU\…\Run` key |
| Settings window (System Settings style) | WinUI `NavigationView` settings window (Windows Settings style) |
| `--selftest` (231 checks) | An xUnit test project with the same scenarios (port `SelfTest.swift`) |
| DMG with designed window | MSIX package or installer, with matching branding |

### Sign-in on Windows (decisions for the owner)
- **Google:** the iOS-type client is meant for Apple devices, so Windows needs its own Google client. Choose one:
  - **Desktop app** type: loopback redirect `http://127.0.0.1:<port>`. It includes a client secret that Google documents as not confidential for installed apps, but it would sit inside the public download.
  - **Universal Windows Platform** type: no secret, but it needs a Microsoft Store listing (Store ID).
- **Microsoft:** the same Entra app works unchanged, as a public client with `http://localhost` and no secret.
- **Scopes are identical** to macOS ([§3](#3-how-it-works-architecture)).

### Logic to port exactly (from `Sources/DesktopBuddy/`)
- Account naming: `AccountConfig.suggestedLabel` and `uniqueLabel` in `SettingsWindow.swift`.
- Client matching: `ClientMatcher` in `Clients.swift`. Senders match an exact address, a domain or a subdomain. Keywords are a whole-word regex. Chats match by picked chat, by name, or for DMs by sender.
- Client health and the generic keyword list (`ClientHealth.swift`); mail filters and mute rules (`MailFilterSettings.swift`).
- Inbox lifecycle (`AppState.swift`): offer, reconcile, dismiss, snooze and wake, chats expire after 24 hours, the seen list is capped at 3,000.
- Polling and sources (`Poller.swift`, `GoogleSources.swift`, `MicrosoftSources.swift`): the same queries.
- Dock placement maths (`Dock.swift`).
- The update check (`Updates.swift`): checksum, then signature, then swap.

### Releases and updates
- **One GitHub release per version for both platforms,** with the same version number. Attach `Desktop-Buddy.dmg` and `.dmg.sha256` (Mac) plus `Desktop-Buddy-Setup.msix` (or `.exe`) and its `.sha256` (Windows). Each app only reads its own asset names, so the Mac updater keeps working.
- **Signing:** without a certificate, Windows shows "Windows protected your PC" (More info → Run anyway). Options: Azure Trusted Signing (about $10 a month) or an OV code-signing certificate. Optional at first.

### What's needed before starting
1. The owner's go-ahead.
2. A Windows 11 PC or virtual machine for testing. On Apple Silicon, Parallels runs Windows 11 on ARM, and WinUI supports ARM64.
3. A decision on the Google client type (above).
4. A decision on code signing (now or later).

---

## 14. Decisions and why (context board)

| Decision | Why |
|---|---|
| Native apps, no backend | Easier security review: data never leaves the Mac, nothing to host |
| Read-only scopes only | Least privilege, and an easier company approval |
| Swift with no third-party libraries | No supply-chain risk, a small app, no licences to check |
| Logos instead of characters or avatars | The owner asked for brand logos only: Dynamatix tree, IE Hub, RiskHawk, Gatehouse |
| Sign in first, name from the email | The original "type your name and email" flow was too much for users |
| Google iOS-type client (no secret) | So the repo and DMG can be public without a secret |
| Consent screen In production (unverified) | Testing mode blocked users who weren't listed and expired sign-ins every 7 days |
| Public GitHub repo | So anyone can download releases. History was squashed once to remove personal data. |
| Daily GitHub update check, then Update and Restart | Users weren't getting new versions. Signature and checksum checks keep in-app updates safe. |
| Self-made "Desktop Buddy Signing" certificate | A stable identity: no Keychain prompts after updates, and the updater only trusts our builds. Free, unlike an Apple Developer ID. |
| Agents per job (website, Mac features, Windows) | Separate chats keep each job's context clean |
| Windows: WinUI 3 / .NET recommended | A native Windows 11 look to match the Mac app's Apple-level design |

---

## 15. Repository map

| Path | What it is |
|---|---|
| `Sources/DesktopBuddy/` | The Mac app (Swift). Start with `App.swift`, `AppState.swift` and `Models.swift`. |
| `Sources/DesktopBuddy/SelfTest.swift` | The built-in tests (`--selftest`) |
| `Resources/` | App icon (`AppIcon.icns`) and built-in logos |
| `build-app.sh` | Build, test, sign, install, package (DMG and checksum) |
| `dmg/` | DMG install window: background generator, background images, layout |
| `docs/` | Screenshots (sample data), `signing.md` |
| `site/` | The website (Next.js, static export) |
| `.claude/agents/` | Agent definitions |
| `.claude/launch.json` | Preview server entry for the website |
| `README.md` | User and admin guide (install, Google/Microsoft setup, team.json, privacy, troubleshooting) |
| `SETUP.md` | This file |
| `CLAUDE.md` | Short pointer for AI agents: read SETUP.md first |
