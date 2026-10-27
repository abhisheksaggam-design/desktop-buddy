import Foundation
import AppKit

/// `DESKTOPBUDDY_HOME=<tmp> DesktopBuddy --selftest`
/// Scenario tests for the logic a user relies on: client rules, inbox state, service switches,
/// reminders, quiet hours, sign-in cancel/restart on the loopback port, parsing. No network,
/// no Keychain, and never your real settings (refuses to run without DESKTOPBUDDY_HOME).
@MainActor
enum SelfTest {
    private static var passed = 0
    private static var failed: [String] = []
    private static var section = ""

    static func run() async -> Int32 {
        guard ProcessInfo.processInfo.environment["DESKTOPBUDDY_HOME"] != nil else {
            print("Refusing to run: set DESKTOPBUDDY_HOME to a temporary folder.")
            return 2
        }
        Keychain.disabled = true
        clientRules()
        mailFilters()
        labelQueries()
        sounds()
        tour()
        placement()
        adminSettings()
        inboxFlows()
        serviceSwitches()
        clientReassignment()
        clientHealth()
        reminders()
        quietHours()
        parsing()
        keychainStore()
        accountNaming()
        await signInLoopback()
        await signInAppScheme()
        updateVersions()

        print("\n\(passed) passed, \(failed.count) failed")
        failed.forEach { print("  ✗ \($0)") }
        return failed.isEmpty ? 0 : 1
    }

    // MARK: - Sign-in through the app's URL scheme (no-secret Google client)

    private static func signInAppScheme() async {
        begin("Sign-in through the app's own link (no secret)")
        var g = AccountConfig(label: "G", email: "")
        g.provider = .google
        g.clientID = "123-abc.apps.googleusercontent.com"
        check("no secret → app link redirect", OAuth.redirectURI(g) == "com.googleusercontent.apps.123-abc:/oauth2redirect")
        var m = AccountConfig(label: "M", email: "")
        m.provider = .microsoft
        check("Microsoft keeps the localhost redirect", OAuth.redirectURI(m) == "http://localhost:\(m.redirectPort)")

        let r = SchemeReceiver()
        let wait = Task { try await r.waitForCallback(timeout: 5) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        check("unrelated link is ignored", !SchemeReceiver.deliver(URL(string: "com.googleusercontent.apps.123-abc:/other")!))
        let took = SchemeReceiver.deliver(URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?code=abc&state=s1")!)
        let params = try? await wait.value
        check("redirect delivers code and state", took && params?["code"] == "abc" && params?["state"] == "s1")
        check("second redirect with nobody waiting is not taken", !SchemeReceiver.deliver(URL(string: "x:/r?code=z")!))

        let c = SchemeReceiver()
        let waitC = Task { try await c.waitForCallback(timeout: 5) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        c.cancel()
        var cancelled = false
        do { _ = try await waitC.value } catch AuthError.cancelled { cancelled = true } catch {}
        check("Cancel ends the wait", cancelled)

        let early = SchemeReceiver()
        early.cancel()
        var earlyCancelled = false
        do { _ = try await early.waitForCallback(timeout: 5) } catch AuthError.cancelled { earlyCancelled = true } catch {}
        check("Cancel before waiting also ends it", earlyCancelled)
    }

    // MARK: - Update check

    private static func updateVersions() {
        begin("Update check")
        check("tag v2.1 → 2.1", UpdateChecker.version(fromTag: "v2.1") == "2.1")
        check("tag without v kept", UpdateChecker.version(fromTag: "2.1.3") == "2.1.3")
        check("2.1 is newer than 2.0", UpdateChecker.isNewer("2.1", than: "2.0"))
        check("2.10 is newer than 2.9", UpdateChecker.isNewer("2.10", than: "2.9"))
        check("3.0 is newer than 2.9.9", UpdateChecker.isNewer("3.0", than: "2.9.9"))
        check("same version is not newer", !UpdateChecker.isNewer("2.1", than: "2.1.0"))
        check("older is not newer", !UpdateChecker.isNewer("2.0", than: "2.1"))
        check("automatic checks are on by default", AppConfig().checkForUpdates)
    }

    // MARK: - Sign-in-first naming

    private static func accountNaming() {
        begin("Account naming after sign-in")
        check("dynamatix.co.uk → Dynamatix", AccountConfig.suggestedLabel(for: "jo@dynamatix.co.uk") == "Dynamatix")
        check("iehub.org → IE Hub", AccountConfig.suggestedLabel(for: "jo@iehub.org") == "IE Hub")
        check("acme-ltd.co.uk → Acme Ltd", AccountConfig.suggestedLabel(for: "jo@acme-ltd.co.uk") == "Acme Ltd")
        check("mail.gatehouse.com → Mail (first real part)", AccountConfig.suggestedLabel(for: "jo@mail.gatehouse.com") == "Mail")
        check("contoso.onmicrosoft.com → Contoso", AccountConfig.suggestedLabel(for: "jo@contoso.onmicrosoft.com") == "Contoso")
        check("gmail.com → Personal", AccountConfig.suggestedLabel(for: "jo@gmail.com") == "Personal")
        check("Mixed case email", AccountConfig.suggestedLabel(for: "Jo@Dynamatix.CO.UK") == "Dynamatix")
        check("Taken name gets a number", AccountConfig.uniqueLabel("Dynamatix", taken: ["Dynamatix"]) == "Dynamatix 2")
        check("Next free number", AccountConfig.uniqueLabel("Dynamatix", taken: ["Dynamatix", "Dynamatix 2"]) == "Dynamatix 3")
        check("Free name unchanged", AccountConfig.uniqueLabel("IE Hub", taken: ["Dynamatix"]) == "IE Hub")
    }

    // MARK: - Harness

    private static func begin(_ name: String) { section = name; print("\n▸ \(name)") }
    private static func check(_ name: String, _ ok: Bool) {
        if ok { passed += 1; print("  ✓ \(name)") } else { failed.append("\(section): \(name)"); print("  ✗ \(name)") }
    }

    private static func mail(_ id: String, account: String, from: String = "Jane", address: String, subject: String,
                             preview: String = "", date: Date = Date()) -> BuddyItem {
        BuddyItem(id: "mail:\(account):\(id)", source: .mail, accountID: account, accountLabel: account,
                  title: subject, from: from, detail: preview, date: date, url: nil, fromAddress: address)
    }
    private static func chat(_ id: String, account: String, space: String, ref: String, text: String = "hi") -> BuddyItem {
        BuddyItem(id: "chat:\(account):\(id)", source: .chat, accountID: account, accountLabel: account,
                  title: space, from: "Sam", detail: text, date: Date(), url: nil, chatRef: ref)
    }

    private static func freshState() -> AppState {
        let s = AppState.shared
        s.resetForTesting()
        s.config.accounts = [
            AccountConfig(id: "acc-g", providerChoice: .google, label: "Dynamatix", email: "me@dynamatix.co.uk"),
            AccountConfig(id: "acc-m", providerChoice: .microsoft, label: "Contoso", email: "me@contoso.com"),
        ]
        s.config.clients = []
        s.config.reminders = []
        s.config.quietStartHour = nil
        s.config.quietEndHour = nil
        s.config.paused = false
        s.config.playSound = false
        s.signedIn = ["acc-g", "acc-m"]          // as if both accounts were signed in
        return s
    }

    // MARK: - Client rules

    private static func clientRules() {
        begin("Client rules")
        var c = ClientConfig(name: "Gatehouse", senders: ["gatehouse.co.uk", "@partner.io", "Boss@Client.com"],
                             keywords: ["FEMA", "  invoice "])
        c.matchChatNames = true
        let m = { (i: BuddyItem) in ClientMatcher.matches(c, i) }

        check("sender domain matches", m(mail("1", account: "a", address: "jane@gatehouse.co.uk", subject: "Hi")))
        check("sender subdomain matches", m(mail("2", account: "a", address: "x@mail.gatehouse.co.uk", subject: "Hi")))
        check("look-alike domain does not match", !m(mail("3", account: "a", address: "x@notgatehouse.co.uk", subject: "Hi")))
        check("rule typed with leading @ works", m(mail("4", account: "a", address: "ops@partner.io", subject: "Hi")))
        check("exact address, any case", m(mail("5", account: "a", address: "boss@client.com", subject: "Hi")))
        check("other address at that domain is not the exact address", !m(mail("6", account: "a", address: "intern@client.com", subject: "Hi")))
        check("keyword in subject, any case", m(mail("7", account: "a", address: "a@b.com", subject: "fema rollout")))
        check("keyword in preview", m(mail("8", account: "a", address: "a@b.com", subject: "Hello", preview: "Attached the invoice.")))
        check("keyword with spaces trimmed", m(mail("9", account: "a", address: "a@b.com", subject: "INVOICE #4")))
        check("keyword is a whole word (FEMA ≠ FEMALE)", !m(mail("10", account: "a", address: "a@b.com", subject: "female founders")))
        check("unrelated mail not matched", !m(mail("11", account: "a", address: "a@b.com", subject: "Lunch?")))
        check("chat named after client matches", m(chat("1", account: "a", space: "Gatehouse Team", ref: "spaces/X")))
        check("chat name is whole-word (Gatehouses ≠ Gatehouse)", !m(chat("2", account: "a", space: "Gatehouses R Us", ref: "spaces/Y")))
        c.matchChatNames = false
        check("chat-name matching can be turned off", !m(chat("3", account: "a", space: "Gatehouse Team", ref: "spaces/X")))
        c.chats = [ChatRef(accountID: "a", chatID: "spaces/PICK", name: "Ops")]
        check("picked chat matches on its account", m(chat("4", account: "a", space: "Ops", ref: "spaces/PICK")))
        check("same chat ID on another account does not", !m(chat("5", account: "b", space: "Ops", ref: "spaces/PICK")))
        let meeting = BuddyItem(id: "meet:a:1", source: .meeting, accountID: "a", title: "Gatehouse sync", date: Date())
        check("meetings are never re-assigned", !m(meeting))
        check("empty keyword is ignored", !ClientMatcher.containsWord("   ", in: "anything"))
        check("short keyword whole-word (Hub ≠ GitHub)", !ClientMatcher.containsWord("Hub", in: "Pushed to GitHub")
              && ClientMatcher.containsWord("Hub", in: "IE Hub weekly"))
        check("keyword with punctuation (R&D)", ClientMatcher.containsWord("R&D", in: "Q4 R&D budget"))
    }

    // MARK: - Muted mail, labels, sounds

    private static func mailFilters() {
        begin("Muted mail")
        let s = freshState()
        var g = s.config.accounts[0]
        g.mutedSenders = ["news.example.com", "noreply@shop.com"]
        g.mutedKeywords = ["newsletter"]
        let muted = { (i: BuddyItem) in MailFilter.isMuted(i, g) }
        check("muted domain", muted(mail("m1", account: "acc-g", address: "a@news.example.com", subject: "Hi")))
        check("muted domain's subdomain", muted(mail("m2", account: "acc-g", address: "a@eu.news.example.com", subject: "Hi")))
        check("look-alike domain is not muted", !muted(mail("m3", account: "acc-g", address: "a@fakenews.example.com", subject: "Hi")))
        check("muted exact address", muted(mail("m4", account: "acc-g", address: "noreply@shop.com", subject: "Order")))
        check("other address at that domain is not", !muted(mail("m5", account: "acc-g", address: "help@shop.com", subject: "Order")))
        check("muted keyword, any case", muted(mail("m6", account: "acc-g", address: "a@b.com", subject: "Our NEWSLETTER")))
        check("keyword is a whole word", !muted(mail("m7", account: "acc-g", address: "a@b.com", subject: "newsletters archive")))
        check("chats are never muted by mail rules", !MailFilter.isMuted(chat("c1", account: "acc-g", space: "newsletter", ref: "s"), g))
        check("old settings have no mute rules", AccountConfig(label: "x", email: "").mutedSenders.isEmpty)

        let keep = mail("f1", account: "acc-g", address: "jo@client.com", subject: "Contract")
        let drop = mail("f2", account: "acc-g", address: "a@news.example.com", subject: "Weekly")
        var r = FetchResult(source: .mail, items: [keep, drop], liveIDs: [keep.id, drop.id])
        let dropped = MailFilter.apply(&r, g)
        check("fetch keeps wanted mail", r.items.map(\.id) == [keep.id])
        check("muted mail leaves the live list too", !r.liveIDs.contains(drop.id) && dropped == [drop.id])

        s.config.clients = [ClientConfig(name: "News", senders: ["news.example.com"])]
        s.offer([drop, keep])
        s.update(g)
        check("saving a mute rule clears matching mail at once", !s.items.contains { $0.id == drop.id })
        check("…and keeps other mail", s.items.contains { $0.id == keep.id })
        let other = mail("f3", account: "acc-m", address: "a@news.example.com", subject: "Weekly")
        check("rules don't leak to another account", !MailFilter.isMuted(other, s.config.accounts[1]))
        s.mutedMail = ["mail:acc-g:old"]
        g.mutedKeywords = []
        s.update(g)
        check("changing rules forgets cached muted mail", s.mutedMail.isEmpty)
    }

    private static func labelQueries() {
        begin("Only mail with chosen labels")
        var g = AccountConfig(providerChoice: .google, label: "G", email: "")
        check("default: inbox only", GmailSource.listQueries(g).map(\.1["q"]) == ["in:inbox is:unread newer_than:2d"])
        g.onlyLabelsList = []
        check("labels chosen but none picked: no mail", GmailSource.listQueries(g).isEmpty)
        g.onlyLabels = [MailLabel(id: "Label_1", name: "Urgent"), MailLabel(id: "Label_2", name: "Client/Acme")]
        let q = GmailSource.listQueries(g)
        check("one Gmail query per label", q.map(\.1["labelIds"]) == ["Label_1", "Label_2"])
        check("labelled mail is found outside the inbox", q.allSatisfy { !($0.1["q"] ?? "").contains("in:inbox") })
        check("queries carry the label name for errors", q.map(\.0) == ["Urgent", "Client/Acme"])

        var m = AccountConfig(providerChoice: .microsoft, label: "M", email: "")
        let since = Date(timeIntervalSince1970: 0)
        check("Outlook default: inbox", OutlookMailSource.listQueries(m, since: since).first?.0.hasSuffix("/mailFolders/inbox/messages") == true)
        m.onlyLabels = [MailLabel(id: "Red", name: "Red"), MailLabel(id: "O'Brien", name: "O'Brien")]
        let o = OutlookMailSource.listQueries(m, since: since)
        check("Outlook: all folders per category", o.count == 2 && o.allSatisfy { $0.0.hasSuffix("/me/messages") })
        check("Outlook category filter", o[0].1["$filter"]?.hasSuffix("categories/any(c:c eq 'Red')") == true)
        check("apostrophes are escaped", o[1].1["$filter"]?.contains("eq 'O''Brien'") == true)
    }

    private static func sounds() {
        begin("Sounds")
        var c = AppConfig()
        check("every type defaults to Glass", ItemSource.allCases.allSatisfy { c.sound(for: $0) == "Glass" })
        c.setSound("Hero", for: .meeting)
        c.setSound(noSound, for: .mail)
        check("a type can have its own sound", c.sound(for: .meeting) == "Hero" && c.sound(for: .chat) == "Glass")
        check("a type can be silent", c.sound(for: .mail) == noSound)
        let items = [mail("x", account: "a", address: "a@b.com", subject: "s"),
                     BuddyItem(id: "meet:a:1", source: .meeting, accountID: "a", title: "Sync", date: Date())]
        check("meeting sound wins over mail in one batch", Sounds.leadSource(of: items) == .meeting)
        check("nothing new, no sound", Sounds.leadSource(of: []) == nil)
        check("all sounds exist on this Mac", Sounds.all.allSatisfy { NSSound(named: $0) != nil })
        let old = try? JSONDecoder().decode(AppConfig.self, from: Data(#"{"accounts":[{"label":"A","email":"a@b.com","id":"1","enabled":true,"watchMail":true,"watchChat":true,"watchMeetings":true,"watchTasks":true,"clientID":"","redirectPort":8766}],"reminders":[],"pollSeconds":60,"meetingLeadMinutes":10,"playSound":true,"paused":false}"#.utf8))
        check("settings from before this update still load", old?.accounts.first?.labelsOnly == false && old?.sound(for: .chat) == "Glass")
    }

    private static func tour() {
        begin("Tour and tips")
        let s = freshState()
        var fresh = AppConfig()
        check("new users get the welcome tour", TourController.shouldShowOnLaunch(fresh))
        fresh.tourSeen = true
        check("…only once", !TourController.shouldShowOnLaunch(fresh))
        check("existing users see it once after updating", TourController.shouldShowOnLaunch(s.config))
        s.config.tourSeen = true
        check("…and not again", !TourController.shouldShowOnLaunch(s.config))
        check("…still signed in with their accounts", s.config.accounts.count == 2)
        check("tips skip the accounts step without accounts", CoachStep.steps(hasAccounts: false) == [.header, .row, .footer])
        check("tips go header → accounts → row → footer", CoachStep.steps(hasAccounts: true) == [.header, .accounts, .row, .footer])

        s.config.tourSeen = nil; s.config.popoverTourSeen = nil; s.coachStep = nil
        s.startCoachMarksIfNeeded()
        check("no tips before the welcome tour", s.coachStep == nil)
        s.config.tourSeen = true
        s.startCoachMarksIfNeeded()
        check("tips start after the tour", s.coachStep == .header)
        s.nextCoachStep(); s.nextCoachStep(); s.nextCoachStep()
        check("Next walks to the last tip", s.coachStep == .footer)
        s.nextCoachStep()
        check("Got It ends the tips and remembers", s.coachStep == nil && s.config.popoverTourSeen == true)
        s.startCoachMarksIfNeeded()
        check("tips don't come back by themselves", s.coachStep == nil)
        s.replayTour()
        s.startCoachMarksIfNeeded()
        check("Show Tour plays the tips again", s.coachStep == .header)
        s.finishCoachMarks()

        check("menu bar shows the count", MenuBarMark.title(count: 3, paused: false) == "3")
        check("no number when nothing waits", MenuBarMark.title(count: 0, paused: false).isEmpty)
        check("no number while paused", MenuBarMark.title(count: 3, paused: true).isEmpty)
    }

    private static func placement() {
        begin("Logos: main display, screen sharing")
        let main = NSRect(x: 0, y: 80, width: 1440, height: 820)       // visible frame above a Dock
        let size = NSSize(width: 200, height: 120)
        let f = OverlayPlacement.frame(size: size, offset: OverlayPlacement.defaultOffset, in: main)
        check("default sits in the bottom-right corner", f.maxX == 1416 && f.minY == 104)
        let far = OverlayPlacement.frame(size: size, offset: CGSize(width: -900, height: 24), in: main)
        check("dragged onto a screen to the right → back on the main display", far.maxX == main.maxX)
        let left = OverlayPlacement.frame(size: size, offset: CGSize(width: 5000, height: 24), in: main)
        check("dragged off the left → stays fully on screen", left.minX == main.minX)
        let up = OverlayPlacement.frame(size: size, offset: CGSize(width: 24, height: 5000), in: main)
        check("never goes under the menu bar", up.maxY == main.maxY)
        let down = OverlayPlacement.frame(size: size, offset: CGSize(width: 24, height: -300), in: main)
        check("never goes under the Dock", down.minY == main.minY)
        let smaller = NSRect(x: 0, y: 0, width: 1280, height: 800)
        let moved = OverlayPlacement.frame(size: size, offset: CGSize(width: 40, height: 60), in: smaller)
        check("keeps its spot from the corner when the display changes", moved.maxX == 1240 && moved.minY == 60)
        let p = NSPoint(x: 1300, y: 200)
        check("offset round-trips", OverlayPlacement.frame(size: size, offset: OverlayPlacement.offset(of: p, in: main), in: main).maxX == 1300)

        let now = Date()
        check("hidden from sharing by default", AppConfig().hidesFromSharing
              && OverlayPlacement.sharingHidden(protection: true, allowedUntil: nil, now: now))
        check("screenshots allowed for the minute", !OverlayPlacement.sharingHidden(protection: true, allowedUntil: now + 60, now: now))
        check("…then hidden again", OverlayPlacement.sharingHidden(protection: true, allowedUntil: now - 1, now: now))
        check("can be turned off for good", !OverlayPlacement.sharingHidden(protection: false, allowedUntil: nil, now: now))
    }

    private static func adminSettings() {
        begin("Admin settings")
        let ready = TeamConfig(googleClientID: "123-abc.apps.googleusercontent.com")
        check("hidden when sign-in is set up", !SettingsRouter.showsAdmin(requested: false, team: ready))
        check("shown when an admin holds Option", SettingsRouter.showsAdmin(requested: true, team: ready))
        check("shown when sign-in isn't set up, to fix it", SettingsRouter.showsAdmin(requested: false, team: TeamConfig()))
        check("Microsoft-only setups count as set up",
              !SettingsRouter.showsAdmin(requested: false, team: TeamConfig(microsoftClientID: "0000")))
    }

    // MARK: - Inbox state

    private static func inboxFlows() {
        begin("Notifications: arrive, dedupe, dismiss, read elsewhere")
        let s = freshState()
        let a = mail("n1", account: "acc-g", address: "x@y.com", subject: "One")
        let b = mail("n2", account: "acc-g", address: "x@y.com", subject: "Two")
        check("new items are shown", s.offer([a, b]) == 2 && s.items.count == 2)
        check("same items again are not repeated", s.offer([a, b]) == 0 && s.items.count == 2)
        s.dismiss(a.id)
        check("Done removes the item", !s.items.contains { $0.id == a.id })
        check("a dismissed item never pops up again", s.offer([a]) == 0)
        let other = mail("n3", account: "acc-m", address: "x@y.com", subject: "Other account")
        s.offer([other])
        s.reconcile(source: .mail, accountID: "acc-g", liveIDs: [])
        check("read in Gmail → disappears", !s.items.contains { $0.id == b.id })
        check("…without touching other accounts", s.items.contains { $0.id == other.id })
        s.clearAll(owner: "acc-m")
        check("Clear on one account only clears that account", s.items.isEmpty)
        check("list closes when nothing is left", s.expanded == false)
    }

    private static func serviceSwitches() {
        begin("Service and account switches")
        let s = freshState()
        s.offer([mail("s1", account: "acc-g", address: "x@y.com", subject: "Mail"),
                 chat("s2", account: "acc-g", space: "Team", ref: "spaces/T"),
                 mail("s3", account: "acc-m", address: "x@y.com", subject: "MS mail")])
        var g = s.account("acc-g")!
        g.watchMail = false
        s.update(g)
        check("turning Mail off clears that account's mail", !s.items.contains { $0.id == "mail:acc-g:s1" })
        check("…but keeps its chats", s.items.contains { $0.id == "chat:acc-g:s2" })
        check("…and other accounts' mail", s.items.contains { $0.id == "mail:acc-m:s3" })
        g.enabled = false
        s.update(g)
        check("turning the account off clears everything from it", !s.items.contains { $0.accountID == "acc-g" })
        s.removeAccount("acc-m")
        check("removing an account removes its items", s.items.isEmpty && s.account("acc-m") == nil)
    }

    private static func clientReassignment() {
        begin("Clients added or changed later")
        let s = freshState()
        let m1 = mail("c1", account: "acc-g", address: "pm@gatehouse.co.uk", subject: "Release")
        let c1 = chat("c2", account: "acc-g", space: "Gatehouse Team", ref: "spaces/G")
        s.offer([m1, c1])
        check("before the client exists, items belong to the account", s.items.allSatisfy { $0.owner == "acc-g" })
        var gh = ClientConfig(name: "Gatehouse", senders: ["gatehouse.co.uk"])
        s.addClient(gh)
        check("adding a client moves matching items under it", s.items.allSatisfy { $0.owner == gh.id })
        check("client shows first, before accounts", s.activeOwners.first == gh.id)
        gh.enabled = false
        s.updateClient(gh)
        check("turning the client off moves them back", s.items.allSatisfy { $0.owner == "acc-g" })
        gh.enabled = true
        gh.accountIDs = ["acc-m"]
        s.updateClient(gh)
        check("client limited to another account doesn't take these", s.items.allSatisfy { $0.owner == "acc-g" })
        s.removeClient(gh.id)
        check("removing the client leaves items with the account", s.items.count == 2)
        let tagged = ClientMatcher.assign([mail("c3", account: "acc-g", address: "a@b.com", subject: "x")], accountID: "acc-g")
        check("no clients → nothing tagged", tagged.first?.clientID == nil)
    }

    private static func clientHealth() {
        begin("Client health: settings that silently break a client")
        let s = freshState()
        let dm = ChatRef(accountID: "acc-g", chatID: "spaces/DM", name: "Sam Taylor", kind: .direct)
        var c = ClientConfig(name: "acme", chats: [dm])
        s.addClient(c)
        check("healthy client has no issues", s.clientIssues(c).isEmpty)

        var g = s.account("acc-g")!
        g.watchChat = false; s.update(g)
        let issues = s.clientIssues(c)
        check("chat off on the chat's account is flagged", issues.contains { $0.chat == dm && $0.text.contains("turned off") })
        check("…with a Turn On fix", issues.contains { $0.fix == .turnOnService("acc-g", .chat) })
        check("account page says who depends on it", s.clientsUsing(g, .chat).map(\.name) == ["acme"])
        s.apply(.turnOnService("acc-g", .chat), client: c.id)
        check("the fix turns chat back on", s.account("acc-g")!.watchChat && s.clientIssues(c).isEmpty)

        g = s.account("acc-g")!; g.enabled = false; s.update(g)
        check("account off is flagged", s.clientIssues(c).contains { $0.fix == .turnOnAccount("acc-g") })
        g.enabled = true; s.update(g)

        c.accountIDs = ["acc-m"]; s.updateClient(c)
        check("chat outside Look in is flagged", s.clientIssues(c).contains { $0.fix == .addToLookIn("acc-g") })
        c.accountIDs = []; s.updateClient(c)

        s.expired.insert("acc-g")
        check("expired sign-in is flagged", s.clientIssues(c).contains { $0.fix == .signIn("acc-g") })
        s.expired.remove("acc-g")

        c.keywords = ["team"]; s.updateClient(c)
        check("generic keyword is flagged", s.clientIssues(c).contains { $0.id == "kw-team" })
        c.keywords = []; c.chats = []; c.matchChatNames = false; s.updateClient(c)
        check("client with no rules is flagged", s.clientIssues(c).contains { $0.id == "norules" })
        c.enabled = false; s.updateClient(c)
        check("client turned off says so (and only that)", s.clientIssues(c).map(\.id) == ["off"])

        c.enabled = true; c.chats = [dm]; s.updateClient(c)
        s.removeAccount("acc-g")
        check("removing an account removes its chats from clients", s.client(c.id)?.chats.isEmpty == true)

        let dmItem = BuddyItem(id: "chat:x:1", source: .chat, accountID: "acc-m", title: "Direct message",
                               from: "Sam Taylor", date: Date(), chatRef: "spaces/OTHER")
        var byName = ClientConfig(name: "Sam"); byName.matchChatNames = true
        check("name matching also covers a DM with that person", ClientMatcher.matches(byName, dmItem))

        check("sender 'gatehouse' (no domain ending) is rejected", TokenField.senderProblem("gatehouse") != nil)
        check("sender with a space is rejected", TokenField.senderProblem("gate house.com") != nil)
        check("half an address is rejected", TokenField.senderProblem("jane@") != nil)
        check("domain and full address are accepted",
              TokenField.senderProblem("gatehouse.co.uk") == nil && TokenField.senderProblem("jane@gatehouse.co.uk") == nil
              && TokenField.senderProblem("@partner.io") == nil)
        check("keywords under 3 letters are rejected", TokenField.keywordProblem("ab") != nil && TokenField.keywordProblem("FEMA") == nil)
    }

    // MARK: - Reminders & quiet hours

    private static func at(_ weekday: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        // A known week: 2026-10-18 is a Sunday (weekday 1).
        var c = DateComponents(year: 2026, month: 10, day: 17 + weekday, hour: hour, minute: minute)
        c.calendar = Calendar.current
        return Calendar.current.date(from: c)!
    }

    private static func reminders() {
        begin("Reminders")
        let s = freshState()
        let r = Reminder(title: "Drink water", everyMinutes: 30, startHour: 9, endHour: 18, weekdays: [2, 3, 4, 5, 6])
        s.config.reminders = [r]
        let id = "reminder:\(r.id.uuidString)"
        Poller.shared.checkReminders(now: at(2, 8, 30))
        check("not before the start hour", !s.items.contains { $0.id == id })
        Poller.shared.checkReminders(now: at(2, 9, 0))
        check("fires inside the window on a weekday", s.items.contains { $0.id == id })
        s.dismiss(id)
        Poller.shared.checkReminders(now: at(2, 9, 20))
        check("does not repeat within the interval", !s.items.contains { $0.id == id })
        Poller.shared.checkReminders(now: at(2, 9, 31))
        check("repeats after the interval, even if dismissed", s.items.contains { $0.id == id })
        Poller.shared.checkReminders(now: at(2, 10, 5))
        check("never stacks: one copy at a time", s.items.filter { $0.id == id }.count == 1)
        s.clearAll()
        s.config.reminders[0].lastFired = nil
        Poller.shared.checkReminders(now: at(1, 11, 0))
        check("skips days that aren't selected (Sunday)", s.items.isEmpty)
        Poller.shared.checkReminders(now: at(2, 18, 0))
        check("stops at the end hour", s.items.isEmpty)
        s.config.reminders[0].enabled = false
        Poller.shared.checkReminders(now: at(3, 10, 0))
        check("switched-off reminder never fires", s.items.isEmpty)
        s.config.reminders[0].enabled = true
        s.config.paused = true
        Poller.shared.checkReminders(now: at(3, 10, 0))
        check("Pause All silences reminders", s.items.isEmpty)
        s.config.paused = false
    }

    private static func quietHours() {
        begin("Quiet hours")
        let s = freshState()
        s.config.quietStartHour = 22; s.config.quietEndHour = 8
        check("overnight window: 23:00 is quiet", s.isQuiet(at: at(3, 23)))
        check("overnight window: 07:59 is quiet", s.isQuiet(at: at(3, 7, 59)))
        check("overnight window: 08:00 is not", !s.isQuiet(at: at(3, 8)))
        check("overnight window: noon is not", !s.isQuiet(at: at(3, 12)))
        s.config.quietStartHour = 13; s.config.quietEndHour = 14
        check("daytime window: 13:30 is quiet", s.isQuiet(at: at(3, 13, 30)))
        s.config.reminders = [Reminder(title: "Stretch", everyMinutes: 15, startHour: 9, endHour: 18, weekdays: Set(1...7))]
        Poller.shared.checkReminders(now: at(3, 13, 30))
        check("reminders wait during quiet hours", s.items.isEmpty)
        s.config.quietStartHour = nil; s.config.quietEndHour = nil
    }

    // MARK: - Parsing

    private static func parsing() {
        begin("Parsing what the APIs send")
        check("Gmail sender with name", GmailSource.senderAddress("Priya Shah <Priya@Gatehouse.co.uk>") == "priya@gatehouse.co.uk")
        check("Gmail sender without name", GmailSource.senderAddress("ops@x.com") == "ops@x.com")
        check("Graph date with 7-digit fraction", graphDate("2026-10-21T09:15:23.1234567Z") != nil)
        check("Graph date without Z (UTC)", graphDate("2026-10-21T09:15:23.0000000") != nil)
        check("Graph UTC date is not shifted", graphDate("2026-10-21T09:15:00.0000000") == isoPlain.date(from: "2026-10-21T09:15:00Z"))
        check("chips: comma list, trimmed, deduped",
              TokenField.merge(" a.com, B.com ,, a.COM ", into: ["b.com"]) == ["b.com", "a.com"])
        check("short ages read like Notification Center",
              shortAgo(Date()) == "now" && shortAgo(Date().addingTimeInterval(-300)) == "5m"
              && shortAgo(Date().addingTimeInterval(-7200)) == "2h" && shortAgo(Date().addingTimeInterval(-3 * 86_400)) == "3d")
        check("team setup: Google needs only the ID (secret optional)", TeamConfig(googleClientID: "x").hasClient(for: .google)
              && !TeamConfig(googleClientSecret: "y").hasClient(for: .google))
        check("team setup: Microsoft needs only the ID", TeamConfig(microsoftClientID: "x").hasClient(for: .microsoft))
        let saved = ChatRef(accountID: "a", chatID: "spaces/DM1", name: "Direct message")
        let relisted = ChatRef(accountID: "a", chatID: "spaces/DM1", name: "Priya Shah", kind: .direct, lastActive: Date())
        check("a picked chat stays picked after its name is resolved", Set([saved]).contains(relisted))
        check("same space ID on another account is a different chat",
              saved != ChatRef(accountID: "b", chatID: "spaces/DM1", name: "Priya Shah"))
    }

    private static func keychainStore() {
        begin("Sign-in storage")
        Keychain.set("token-1", for: "refresh.t")
        check("stores and reads a value", Keychain.get("refresh.t") == "token-1")
        Keychain.set("token-2", for: "refresh.t")
        check("overwrites", Keychain.get("refresh.t") == "token-2")
        Keychain.set(nil, for: "refresh.t")
        check("removes", Keychain.get("refresh.t") == nil)
    }

    // MARK: - Sign-in loopback (real local socket)

    private static func signInLoopback() async {
        begin("Browser sign-in: cancel, restart, callback")
        let port: UInt16 = 18_765
        // 1) Cancel a sign-in nobody finishes (tab closed / wrong browser profile).
        let r1 = LoopbackReceiver(port: port)
        let t1 = Task { try await r1.waitForCallback(timeout: 30) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        let started = Date()
        r1.cancel()
        var cancelled = false
        do { _ = try await t1.value } catch AuthError.cancelled { cancelled = true } catch {}
        check("Cancel ends the wait right away", cancelled && Date().timeIntervalSince(started) < 2)

        // 2) The port is free again for a new attempt; a stray request doesn't end it; the real callback does.
        try? await Task.sleep(nanoseconds: 300_000_000)
        let r2 = LoopbackReceiver(port: port)
        let t2 = Task { try await r2.waitForCallback(timeout: 30) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        let stray = await httpGet("http://localhost:\(port)/favicon.ico")
        check("stray browser request is ignored (404)", stray == 404)
        let ok = await httpGet("http://localhost:\(port)/oauth2callback?code=abc&state=xyz")
        check("callback page loads for the user", ok == 200)
        let params = try? await t2.value
        check("port is reusable after cancel; callback returns the code", params?["code"] == "abc" && params?["state"] == "xyz")

        // 3) Provider error (user pressed Cancel on Google's page) comes back as an error, not a hang.
        let r3 = LoopbackReceiver(port: port)
        let t3 = Task { try await r3.waitForCallback(timeout: 30) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        _ = await httpGet("http://localhost:\(port)/?error=access_denied&state=xyz")
        let p3 = try? await t3.value
        check("'access denied' returns instead of waiting", p3?["error"] == "access_denied")

        // 4) Port already taken → clear message instead of a silent failure.
        let blocker = LoopbackReceiver(port: port)
        let tb = Task { try await blocker.waitForCallback(timeout: 30) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        let r4 = LoopbackReceiver(port: port)
        var busy = false
        do { _ = try await r4.waitForCallback(timeout: 3) } catch AuthError.portInUse { busy = true } catch {}
        check("busy port gives a clear error", busy)
        blocker.cancel(); _ = try? await tb.value
    }

    private static func httpGet(_ url: String) async -> Int {
        var req = URLRequest(url: URL(string: url)!)
        req.timeoutInterval = 5
        let resp = try? await URLSession.shared.data(for: req)
        return (resp?.1 as? HTTPURLResponse)?.statusCode ?? -1
    }
}
