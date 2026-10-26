import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// System Settings–style window: sidebar of accounts + app sections, detail on the right.

enum SettingsPane: Hashable {
    case account(String), client(String), general, appearance, reminders, team
}

@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var selection: SettingsPane? = .general
    @Published var addingProvider: Provider?
    @Published var showingProviderPicker = false
    @Published var addingClient = false
}

struct SettingsRoot: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var router = SettingsRouter.shared

    var body: some View {
        // Custom two-pane layout (not NavigationSplitView): sidebar material + content surface,
        // with no divider or titlebar edge lines anywhere.
        HStack(spacing: 0) {
            List(selection: $router.selection) {
                Section("Accounts") {
                    ForEach(state.config.accounts) { a in
                        AccountSidebarRow(account: a).tag(SettingsPane.account(a.id))
                    }
                    Button { router.showingProviderPicker = true } label: {
                        Label("Add Account…", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                Section("Clients") {
                    ForEach(state.config.clients) { c in
                        ClientSidebarRow(client: c).tag(SettingsPane.client(c.id))
                    }
                    Button { router.addingClient = true } label: {
                        Label("Add Client…", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                Section("Desktop Buddy") {
                    sidebarItem("General", "gearshape.fill", .gray, .general)
                    sidebarItem("Appearance", "paintpalette.fill", .indigo, .appearance)
                    sidebarItem("Reminders", "bell.badge.fill", .teal, .reminders)
                    sidebarItem("Team Setup", "person.3.fill", .blue, .team)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(width: 250)
            .padding(.top, 28)               // clear the traffic lights
            .background(SidebarMaterial().ignoresSafeArea())

            Group {
                switch router.selection {
                case .account(let id) where state.account(id) != nil: AccountDetailView(accountID: id)
                case .client(let id) where state.client(id) != nil: ClientDetailView(clientID: id)
                case .appearance: AppearancePane()
                case .reminders: RemindersPane()
                case .team: TeamSetupPane()
                default:
                    if state.config.accounts.isEmpty && router.selection == nil { NoAccountsView() } else { GeneralPane() }
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                if state.config.paused {
                    HStack(spacing: 10) {
                        Image(systemName: "moon.fill").foregroundStyle(.indigo)
                        Text("Notifications are paused. Nothing is checked or shown until you resume.")
                        Spacer()
                        Button("Resume") { state.config.paused = false }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.indigo.opacity(0.12))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        }
        .ignoresSafeArea(edges: .top)
        .frame(minWidth: 760, minHeight: 540)
        .sheet(isPresented: $router.showingProviderPicker) { ProviderPickerSheet() }
        .sheet(item: $router.addingProvider) { p in AddAccountSheet(provider: p) }
        .sheet(isPresented: $router.addingClient) { AddClientSheet() }
    }

    private func sidebarItem(_ title: String, _ symbol: String, _ tint: Color, _ pane: SettingsPane) -> some View {
        Label { Text(title) } icon: { SettingsIcon(symbol: symbol, tint: tint) }.tag(pane)
    }
}

// MARK: - Shared bits

/// Rounded-square coloured icon, like System Settings.
struct SettingsIcon: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 20
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay(
                // Scale any SF Symbol (wide ones like person.3 included) to fit the tile, like System Settings.
                Image(systemName: symbol)
                    .resizable()
                    .symbolRenderingMode(.monochrome)
                    .fontWeight(.semibold)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .padding(size * 0.2)
            )
    }
}

/// Provider mark drawn natively (no logo assets): Google "G", Microsoft four squares.
struct ProviderBadge: View {
    var provider: Provider
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(.white)
                .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).stroke(.black.opacity(0.1), lineWidth: 0.5))
            switch provider {
            case .google:
                Text("G").font(.system(size: size * 0.62, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.26, green: 0.52, blue: 0.96), Color(red: 0.92, green: 0.26, blue: 0.21),
                                                             Color(red: 0.98, green: 0.74, blue: 0.02), Color(red: 0.2, green: 0.66, blue: 0.33)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
            case .microsoft:
                let s = size * 0.26
                VStack(spacing: size * 0.05) {
                    HStack(spacing: size * 0.05) {
                        Rectangle().fill(Color(red: 0.95, green: 0.31, blue: 0.13)).frame(width: s, height: s)
                        Rectangle().fill(Color(red: 0.5, green: 0.73, blue: 0.0)).frame(width: s, height: s)
                    }
                    HStack(spacing: size * 0.05) {
                        Rectangle().fill(Color(red: 0.0, green: 0.64, blue: 0.94)).frame(width: s, height: s)
                        Rectangle().fill(Color(red: 1.0, green: 0.73, blue: 0.0)).frame(width: s, height: s)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct StatusDot: View {
    enum Kind { case ok, warning, off }
    var kind: Kind
    var body: some View {
        Circle().fill(kind == .ok ? Color.green : (kind == .warning ? Color.orange : Color.secondary.opacity(0.5)))
            .frame(width: 7, height: 7)
    }
}

private struct AccountSidebarRow: View {
    let account: AccountConfig
    @ObservedObject var state = AppState.shared
    var body: some View {
        HStack(spacing: 8) {
            AccountMark(account: account, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(account.label).lineLimit(1)
                Text(account.email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            StatusDot(kind: dot)
        }
        .padding(.vertical, 1)
    }
    private var dot: StatusDot.Kind {
        if !account.enabled { return .off }
        if state.expired.contains(account.id) { return .warning }
        if !state.signedIn.contains(account.id) { return .off }
        return state.errorCount(for: account.id) > 0 ? .warning : .ok
    }
}

/// A short helper explaining a section, in Apple's footnote style.
struct Footnote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Empty state

private struct NoAccountsView: View {
    @ObservedObject var router = SettingsRouter.shared
    var body: some View {
        VStack(spacing: 18) {
            AppMark(size: 84)
            Text("Sign In to Get Started").font(.title2.weight(.semibold))
            Text("Sign in with the Google Workspace or Microsoft 365 account you work in.\nMail, chats, meetings and tasks are all covered by one sign-in.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { router.addingProvider = .google } label: {
                    Label { Text("Sign in with Google") } icon: { ProviderBadge(provider: .google, size: 16) }
                }
                Button { router.addingProvider = .microsoft } label: {
                    Label { Text("Sign in with Microsoft") } icon: { ProviderBadge(provider: .microsoft, size: 16) }
                }
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Account detail

struct AccountDetailView: View {
    let accountID: String
    @ObservedObject var state = AppState.shared
    @Local private var confirmRemove = false
    @Local private var showAdvanced = false
    @Local private var secretDraft = ""

    private var binding: Binding<AccountConfig> {
        Binding(get: { state.account(accountID) ?? AccountConfig(label: "", email: "") },
                set: { state.update($0) })
    }

    var body: some View {
        let a = binding.wrappedValue
        let signedIn = state.signedIn.contains(a.id)
        Form {
            // Header
            Section {
                HStack(spacing: 14) {
                    OwnerBuddy(owner: a.id, excited: false, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(a.label).font(.title2.weight(.semibold))
                        Text(a.email).foregroundStyle(.secondary)
                        HStack(spacing: 5) {
                            ProviderBadge(provider: a.provider, size: 14)
                            Text(a.provider.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("Account on", isOn: binding.enabled).toggleStyle(.switch).labelsHidden()
                        .help(a.enabled ? "Turn off to stop checking this account" : "Turn on to start checking")
                }
                .padding(.vertical, 4)
            }

            // Connection
            Section {
                ConnectionRow(account: a) { signIn(a) }
            }

            // Services (the on/off switches)
            Section {
                ServiceRow(account: a, source: .mail, name: a.provider.mailName, symbol: "envelope.fill", tint: .blue,
                           isOn: binding.watchMail)
                ServiceRow(account: a, source: .chat, name: a.provider.chatName, symbol: "bubble.left.and.bubble.right.fill",
                           tint: .green, isOn: binding.watchChat)
                ServiceRow(account: a, source: .meeting, name: "Meetings", symbol: "video.fill", tint: .indigo,
                           isOn: binding.watchMeetings)
                ServiceRow(account: a, source: .task, name: a.provider.tasksName, symbol: "checklist", tint: .orange,
                           isOn: binding.watchTasks)
            } header: {
                Text("Notify Me About")
            } footer: {
                Footnote("Turning a service off stops checking it straight away and clears its notifications. Desktop Buddy only reads; it never sends, changes or deletes anything.")
            }

            // Appearance
            Section("Appearance") {
                TextField("Name", text: binding.label)
                LabeledContent("Color") { TintPicker(selection: binding.tint) }
                LabeledContent("Logo") {
                    HStack(spacing: 8) {
                        if a.logoPath != nil {
                            Button("Use Default") { var x = a; x.logoPath = nil; state.update(x) }
                        }
                        Button("Choose…") {
                            if let src = Logos.choose(), let path = Logos.importImage(from: src, as: "account") {
                                var x = a; x.logoPath = path; state.update(x)
                            }
                        }
                    }
                }
            }

            // Advanced
            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    TextField("Email", text: binding.email)
                    TextField("Client ID (optional)", text: binding.clientID, prompt: Text("Uses the team default"))
                    if a.provider == .google {
                        SecureField("Client secret (optional)", text: $secretDraft, prompt: Text("Uses the team default"))
                            .onSubmit { Keychain.set(secretDraft, for: OAuth.secretKey(a.id)); secretDraft = "" }
                    } else {
                        TextField("Tenant", text: Binding(get: { a.tenant ?? "" },
                                                          set: { var x = a; x.tenant = $0.isEmpty ? nil : $0; state.update(x) }),
                                  prompt: Text("organizations"))
                    }
                    LabeledContent("Sign-in port") {
                        TextField("", value: binding.redirectPort, format: .number.grouping(.never)).frame(width: 70)
                    }
                    LabeledContent("Redirect URI") {
                        HStack {
                            Text(OAuth.redirectURI(a)).font(.callout.monospaced()).textSelection(.enabled)
                            Button { copy(OAuth.redirectURI(a)) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section {
                HStack {
                    if signedIn {
                        Button("Sign Out") { Task { await OAuth.shared.signOut(a); state.refreshSignedIn() } }
                    }
                    Spacer()
                    Button("Remove Account…", role: .destructive) { confirmRemove = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(a.label)
        .confirmationDialog("Remove \(a.label)?", isPresented: $confirmRemove) {
            Button("Remove Account", role: .destructive) {
                SettingsRouter.shared.selection = .general
                state.removeAccount(a.id)
            }
        } message: {
            Text("Desktop Buddy will sign out and forget this account on this Mac. Nothing changes in \(a.provider.name).")
        }
    }

    private func signIn(_ a: AccountConfig) {
        Task { if await SignInCenter.shared.start(a) { await Poller.shared.poll(a) } }
    }
}

private struct ServiceRow: View {
    let account: AccountConfig
    let source: ItemSource
    let name: String
    let symbol: String
    let tint: Color
    @Binding var isOn: Bool
    @ObservedObject var state = AppState.shared

    var body: some View {
        let s = state.status(account.id, source)
        HStack(spacing: 10) {
            SettingsIcon(symbol: symbol, tint: isOn ? tint : .gray, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Group {
                    if !isOn || !account.enabled {
                        let users = state.clientsUsing(account, source).map(\.name)
                        if users.isEmpty {
                            Text("Off")
                        } else {
                            Text("Off · \(ListFormatter.localizedString(byJoining: users)) won't get \(source == .chat ? "chats" : "mail") from \(account.label)")
                                .foregroundStyle(.orange)
                        }
                    } else if state.needsSignIn(account.id) {
                        Text("Paused until you sign in")
                    } else if let err = s.error {
                        Text(err).foregroundStyle(.orange).lineLimit(2)
                    } else if let t = s.lastChecked {
                        Text("\(s.count == 0 ? "Nothing new" : "\(s.count) waiting") · checked \(t.formatted(.relative(presentation: .named)))")
                    } else {
                        Text("Waiting for first check")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isOn, let url = s.fixURL {
                Button("Fix…") { NSWorkspace.shared.open(url) }.controlSize(.small)
                    .help("Opens the admin console page that turns this API on")
            }
            Toggle(name, isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }
}

struct TintPicker: View {
    @Binding var selection: AccountTint
    var body: some View {
        HStack(spacing: 7) {
            ForEach(AccountTint.allCases) { t in
                Circle().fill(t.color.gradient)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().fill(.white).frame(width: 6).opacity(selection == t ? 1 : 0))
                    .overlay(Circle().stroke(.black.opacity(0.12), lineWidth: 0.5))
                    .contentShape(Circle())
                    .onTapGesture { selection = t }
                    .help(t.rawValue.capitalized)
                    .accessibilityLabel(t.rawValue.capitalized)
                    .accessibilityAddTraits(selection == t ? .isSelected : [])
            }
        }
    }
}

private func copy(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

// MARK: - Add account

private struct ProviderPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var router = SettingsRouter.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose an Account Type").font(.title3.weight(.semibold))
            ForEach(Provider.allCases) { p in
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { router.addingProvider = p }
                } label: {
                    HStack(spacing: 14) {
                        ProviderBadge(provider: p, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.headline)
                            Text(p.services).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(22)
        .frame(width: 440)
    }
}

/// Sign in first: the person picks their account in the browser, and the app fills in the
/// email and a name from it. Nothing to type unless the team hasn't shared a sign-in client yet.
struct AddAccountSheet: View {
    let provider: Provider
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state = AppState.shared
    @Local private var draft = AccountConfig(label: "", email: "")
    @Local private var prepared = false
    @Local private var phase = Phase.form
    @Local private var error: String? = nil

    enum Phase { case form, waiting, done }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ProviderBadge(provider: provider, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sign In with \(provider == .google ? "Google" : "Microsoft")").font(.title3.weight(.semibold))
                    Text(provider.services).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding([.horizontal, .top], 22)
            .padding(.bottom, 8)

            switch phase {
            case .form: form
            case .waiting: waiting
            case .done: done
            }
        }
        .frame(width: 520)
        .onAppear {
            guard !prepared else { return }
            prepared = true
            draft.provider = provider
            draft.redirectPort = 8766
            // Spread colours so each new account looks different.
            let n = state.config.accounts.count
            draft.tint = AccountTint.allCases[(n + (provider == .microsoft ? 1 : 0)) % AccountTint.allCases.count]
            // Team sign-in client is installed: go straight to the browser.
            if !needsClient { start() }
        }
    }

    private var needsClient: Bool { !TeamConfig.current.hasClient(for: provider) }

    private var canSubmit: Bool { !needsClient }

    private var form: some View {
        VStack(spacing: 0) {
            Form {
                Section("Desktop Buddy will be able to") {
                    ForEach(OAuth.permissionSummary(provider), id: \.self) { line in
                        Label(line, systemImage: "checkmark.circle.fill").symbolRenderingMode(.multicolor)
                    }
                }
                if needsClient {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Sign-in isn't set up in this copy yet").font(.headline)
                                Text("Your admin sets up \(provider == .google ? "Google" : "Microsoft") sign-in once for the whole team and shares a setup file. Import it here, or ask them for a copy of Desktop Buddy with sign-in built in.")
                                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: "person.badge.key.fill").foregroundStyle(.orange)
                        }
                        HStack {
                            Spacer()
                            Button("Import Setup File…") { importSetupFile() }
                        }
                    }
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
            }
            .formStyle(.grouped)
            .frame(height: needsClient ? 430 : 260)

            HStack {
                Button("Cancel") { SignInCenter.shared.cancel(draft.id); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Sign In with \(provider == .google ? "Google" : "Microsoft")…") { start() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canSubmit)
            }
            .padding(18)
        }
    }

    private var waiting: some View {
        SignInWaitingView(accountID: draft.id, email: "")
            .padding(24)
            .frame(maxWidth: .infinity)
            .onChange(of: SignInCenter.shared.isWaiting(draft.id)) { _, w in
                // Cancel pressed: back to the form (success moves to .done in start()).
                if !w && phase == .waiting && !state.signedIn.contains(draft.id) { phase = .form }
            }
    }

    private var done: some View {
        VStack(spacing: 12) {
            LogoTile(url: Logos.url(path: draft.logoPath, name: draft.label, email: draft.email),
                     name: draft.label, tint: draft.tint.color, size: 72)
                .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
            Text("You're Connected").font(.title3.weight(.semibold))
            Text(draft.email).foregroundStyle(.secondary)
            Form {
                TextField("Name", text: $draft.label, prompt: Text("e.g. Dynamatix"))
            }
            .formStyle(.grouped)
            .frame(width: 360, height: 70)
            Text("Mail, chats, meetings and tasks are on. You can turn any of them off in Settings.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Done") {
                var a = draft
                a.label = a.label.trimmingCharacters(in: .whitespaces)
                if a.label.isEmpty { a.label = AccountConfig.suggestedLabel(for: a.email) }
                state.update(a)
                SettingsRouter.shared.selection = .account(a.id)
                dismiss()
            }
            .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    private func importSetupFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let cfg = JSONFile.load(TeamConfig.self, from: url) else { return }
        guard cfg.hasClient(for: provider) else {
            error = "That file doesn't include a \(provider.name) sign-in client."
            return
        }
        TeamConfig.installLocal(cfg)
        start()
    }

    private func start() {
        error = nil
        phase = .waiting
        let account = draft
        Task {
            guard await SignInCenter.shared.start(account) else {
                self.error = SignInCenter.shared.errors[account.id]
                SignInCenter.shared.clearError(account.id)
                phase = .form
                return
            }
            // Whoever signed in is the account being added.
            guard let email = (try? await OAuth.signedInEmails(account))?.first else {
                await OAuth.shared.forget(account)
                self.error = "Signed in, but \(provider.name) didn't say which account it was. Please try again."
                phase = .form
                return
            }
            if let existing = state.config.accounts.first(where: { $0.provider == provider && $0.email.caseInsensitiveCompare(email) == .orderedSame }) {
                await OAuth.shared.forget(account)
                self.error = "\(email) is already added as “\(existing.label)”. Choose a different account to add another one."
                phase = .form
                return
            }
            var a = account
            a.email = email
            a.label = AccountConfig.uniqueLabel(AccountConfig.suggestedLabel(for: email),
                                                taken: Set(state.config.accounts.map(\.label)))
            draft = a
            state.addAccount(a)
            phase = .done
            await Poller.shared.poll(a)
        }
    }
}

extension AccountConfig {
    /// A friendly name from the email's domain: "jo@dynamatix.co.uk" → "Dynamatix", "jo@acme-ltd.com" → "Acme Ltd".
    static func suggestedLabel(for email: String) -> String {
        let domain = email.split(separator: "@").last.map { $0.lowercased() } ?? ""
        let known = ["dynamatix.co.uk": "Dynamatix", "dynamatix.com": "Dynamatix", "iehub.org": "IE Hub"]
        if let name = known[domain] { return name }
        let personal: Set<String> = ["gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "icloud.com"]
        if personal.contains(domain) { return "Personal" }
        let generic: Set<String> = ["co", "com", "org", "net", "io", "ac", "gov", "edu", "uk", "us", "in", "au", "ltd", "plc", "onmicrosoft"]
        let parts = domain.split(separator: ".").map(String.init)
        guard let name = parts.first(where: { !generic.contains($0) }) ?? parts.first, !name.isEmpty else { return "Account" }
        return name.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// "Dynamatix" → "Dynamatix 2" when that name is already used.
    static func uniqueLabel(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var state = AppState.shared
    @Local private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Local private var loginError: String? = nil

    var body: some View {
        Form {
            Section {
                Toggle("Open at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister(); loginError = nil }
                        catch { loginError = error.localizedDescription; launchAtLogin = !on }
                    }
                if SMAppService.mainApp.status == .requiresApproval {
                    LabeledContent("Needs your approval in System Settings") {
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Pause All Notifications", isOn: $state.config.paused)
            } footer: {
                Footnote("While paused, Desktop Buddy stops checking every account and hides the logos on your screen.")
            }

            Section("Checking") {
                Picker("Check accounts every", selection: $state.config.pollSeconds) {
                    Text("30 seconds").tag(30); Text("1 minute").tag(60); Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300); Text("15 minutes").tag(900)
                }
                .onChange(of: state.config.pollSeconds) { _, _ in Poller.shared.start() }
                Picker("Warn about meetings", selection: $state.config.meetingLeadMinutes) {
                    Text("2 minutes before").tag(2); Text("5 minutes before").tag(5)
                    Text("10 minutes before").tag(10); Text("15 minutes before").tag(15)
                }
            }

            Section {
                Toggle("Play Sound", isOn: $state.config.playSound)
                Toggle("Quiet Hours", isOn: Binding(
                    get: { state.config.quietStartHour != nil },
                    set: { on in
                        state.config.quietStartHour = on ? 22 : nil
                        state.config.quietEndHour = on ? 8 : nil
                    }))
                if let s = state.config.quietStartHour, let e = state.config.quietEndHour {
                    Picker("From", selection: Binding(get: { s }, set: { state.config.quietStartHour = $0 })) {
                        ForEach(0..<24, id: \.self) { Text(hourText($0)).tag($0) }
                    }
                    Picker("To", selection: Binding(get: { e }, set: { state.config.quietEndHour = $0 })) {
                        ForEach(0..<24, id: \.self) { Text(hourText($0)).tag($0) }
                    }
                    if s == e {
                        Label("Start and end are the same, so quiet hours are off. Pick different times.",
                              systemImage: "exclamationmark.circle.fill").font(.callout).foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Alerts")
            } footer: {
                Footnote("During quiet hours nothing pops up. Anything that arrives waits until quiet hours end.")
            }

            UpdatesSection()

            Section {
                LabeledContent("Your data") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.supportDir]) }
                }
            } header: {
                Text("Privacy")
            } footer: {
                Footnote("Everything stays on this Mac. Sign-ins are stored in your Keychain, and Desktop Buddy talks only to Google and Microsoft (plus GitHub, to check for updates). There are no servers of ours and no AI involved.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

func hourText(_ h: Int) -> String {
    var c = DateComponents(); c.hour = h
    return Calendar.current.date(from: c).map { $0.formatted(date: .omitted, time: .shortened) } ?? "\(h):00"
}

// MARK: - Appearance

private struct AppearancePane: View {
    @ObservedObject var state = AppState.shared
    var body: some View {
        Form {
            Section {
                ForEach(state.config.accounts) { a in
                    LogoRow(owner: a.id, name: a.label, custom: a.logoPath != nil) { path in
                        var x = a; x.logoPath = path; state.update(x)
                    }
                }
                ForEach(state.config.clients) { c in
                    LogoRow(owner: c.id, name: c.name, custom: c.logoPath != nil) { path in
                        var x = c; x.logoPath = path; state.updateClient(x)
                    }
                }
                LogoRow(owner: reminderOwner, name: "Reminders", custom: state.config.reminderLogoPath != nil) { path in
                    state.config.reminderLogoPath = path
                }
            } header: {
                Text("Logos")
            } footer: {
                Footnote("Each account and client shows its own logo on screen, so you know who a notification is for at a glance. A square PNG works best.")
            }

            Section("Size") {
                HStack {
                    Image(systemName: "app").font(.caption)
                    Slider(value: $state.config.characterScale, in: 0.5...1.2)
                    Image(systemName: "app").font(.title3)
                    Text("\(Int(state.config.characterScale * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                LabeledContent("Position") {
                    Button("Move Back to Corner") { OverlayController.shared.resetPosition() }
                }
                LabeledContent("Preview") {
                    Button("Show Sample Notifications") { AppDelegate.sendTestItems() }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}

/// One owner's logo with Choose… / Use Default.
private struct LogoRow: View {
    let owner: String
    let name: String
    let custom: Bool
    let set: (String?) -> Void
    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if custom { Button("Use Default") { set(nil) } }
                Button("Choose…") {
                    if let src = Logos.choose(), let path = Logos.importImage(from: src, as: "logo") { set(path) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                OwnerBuddy(owner: owner, excited: false, size: 28).shadow(radius: 0)
                Text(name)
            }
        }
    }
}

// MARK: - Reminders

private struct RemindersPane: View {
    @ObservedObject var state = AppState.shared
    @Local private var editing: Reminder? = nil

    var body: some View {
        Form {
            Section {
                if state.config.reminders.isEmpty {
                    Text("No reminders yet").foregroundStyle(.secondary)
                }
                ForEach($state.config.reminders) { $r in
                    HStack(spacing: 10) {
                        Text(r.emoji).font(.title2).frame(width: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.title)
                            Text("Every \(r.everyMinutes) min · \(hourText(r.startHour))–\(hourText(r.endHour)) · \(daysText(r.weekdays))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editing = r }.buttonStyle(.borderless)
                        Toggle(r.title, isOn: $r.enabled).toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    .contextMenu {
                        Button("Edit…") { editing = r }
                        Button("Delete", role: .destructive) { state.config.reminders.removeAll { $0.id == r.id } }
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Footnote("Reminders run on this Mac. They work offline and don't need any account.")
            }
            Section {
                Button { editing = Reminder(title: "", emoji: "⏰") } label: { Label("Add Reminder…", systemImage: "plus") }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Reminders")
        .sheet(item: $editing) { r in
            ReminderEditor(reminder: r) { saved in
                if let i = state.config.reminders.firstIndex(where: { $0.id == saved.id }) {
                    state.config.reminders[i] = saved
                } else {
                    state.config.reminders.append(saved)
                }
            } onDelete: { id in
                state.config.reminders.removeAll { $0.id == id }
            }
        }
    }
}

func daysText(_ d: Set<Int>) -> String {
    if d == [2, 3, 4, 5, 6] { return "Weekdays" }
    if d == [1, 7] { return "Weekends" }
    if d.count == 7 { return "Every day" }
    let names = Calendar.current.shortWeekdaySymbols
    return d.sorted().map { names[$0 - 1] }.joined(separator: ", ")
}

private struct ReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    let original: Reminder
    let onSave: (Reminder) -> Void
    let onDelete: (UUID) -> Void
    @Local private var r: Reminder

    init(reminder: Reminder, onSave: @escaping (Reminder) -> Void, onDelete: @escaping (UUID) -> Void) {
        original = reminder
        self.onSave = onSave
        self.onDelete = onDelete
        _r = Local(wrappedValue: reminder)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        TextField("Emoji", text: $r.emoji).frame(width: 44).multilineTextAlignment(.center)
                        TextField("Title", text: $r.title, prompt: Text("Drink a glass of water"))
                    }
                    TextField("Note", text: $r.note, prompt: Text("Optional"))
                }
                Section("Schedule") {
                    Picker("Repeat every", selection: $r.everyMinutes) {
                        ForEach([15, 20, 30, 45, 60, 90, 120, 180, 240], id: \.self) { m in
                            Text(m < 60 ? "\(m) minutes" : (m % 60 == 0 ? "\(m / 60) hour\(m == 60 ? "" : "s")" : "\(m) minutes")).tag(m)
                        }
                    }
                    Picker("From", selection: $r.startHour) { ForEach(0..<24, id: \.self) { Text(hourText($0)).tag($0) } }
                    Picker("Until", selection: $r.endHour) { ForEach(1..<25, id: \.self) { Text(hourText($0 % 24)).tag($0) } }
                    LabeledContent("On") {
                        HStack(spacing: 3) {
                            ForEach(1...7, id: \.self) { day in
                                let on = r.weekdays.contains(day)
                                Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(on ? Color.accentColor : Color.secondary.opacity(0.15)))
                                    .foregroundStyle(on ? .white : .primary)
                                    .contentShape(Circle())
                                    .onTapGesture { if on { r.weekdays.remove(day) } else { r.weekdays.insert(day) } }
                                    .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                                    .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if AppState.shared.config.reminders.contains(where: { $0.id == r.id }) {
                    Button("Delete", role: .destructive) { onDelete(r.id); dismiss() }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(r); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(r.title.trimmingCharacters(in: .whitespaces).isEmpty || r.weekdays.isEmpty || r.endHour <= r.startHour)
            }
            .padding(16)
        }
        .frame(width: 460, height: 430)
    }
}

// MARK: - Team setup

private struct TeamSetupPane: View {
    @Local private var team = TeamConfig.current
    @Local private var saved = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Setup file", value: TeamConfig.source)
                LabeledContent {
                    Label(team.hasClient(for: .google) ? "Ready" : "Not set",
                          systemImage: team.hasClient(for: .google) ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(team.hasClient(for: .google) ? .green : .secondary)
                } label: {
                    HStack(spacing: 6) { ProviderBadge(provider: .google, size: 16); Text("Google Workspace") }
                }
                LabeledContent {
                    Label(team.hasClient(for: .microsoft) ? "Ready" : "Not set",
                          systemImage: team.hasClient(for: .microsoft) ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(team.hasClient(for: .microsoft) ? .green : .secondary)
                } label: {
                    HStack(spacing: 6) { ProviderBadge(provider: .microsoft, size: 16); Text("Microsoft 365") }
                }
            } header: {
                Text("Team")
            } footer: {
                Footnote("With a team setup file, teammates just choose Add Account and sign in. No client IDs needed.")
            }

            Section {
                HStack {
                    Button("Import Setup File…") { importFile() }
                    Button("Export Setup File…") { exportFile() }
                    Spacer()
                }
            }

            Section {
                TextField("Google client ID", text: Binding(get: { team.googleClientID ?? "" }, set: { team.googleClientID = $0 }))
                SecureField("Google client secret", text: Binding(get: { team.googleClientSecret ?? "" }, set: { team.googleClientSecret = $0 }))
                TextField("Microsoft client ID", text: Binding(get: { team.microsoftClientID ?? "" }, set: { team.microsoftClientID = $0 }))
                TextField("Microsoft tenant", text: Binding(get: { team.microsoftTenant ?? "" }, set: { team.microsoftTenant = $0 }),
                          prompt: Text("organizations"))
                HStack {
                    Spacer()
                    if saved { Label("Saved", systemImage: "checkmark").foregroundStyle(.green) }
                    Button("Save on This Mac") { save() }.buttonStyle(.borderedProminent)
                }
            } header: {
                Text("For Admins")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Footnote("Google: in Google Cloud Console create an OAuth client of type Desktop app, enable Gmail, Calendar, Chat, Tasks and People APIs, and configure the Chat app. Microsoft: in Entra admin center register an app, add the Mobile and desktop platform with redirect http://localhost, allow public client flows, and add delegated Graph permissions User.Read, Mail.Read, Calendars.Read, Chat.Read and Tasks.Read.")
                    HStack {
                        Link("Google Cloud Console", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                        Link("Microsoft Entra admin center", destination: URL(string: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade")!)
                    }
                    .font(.footnote)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Team Setup")
    }

    private var localURL: URL { Paths.supportDir.appendingPathComponent("team.json") }

    private func save() {
        JSONFile.save(team, to: localURL)
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let cfg = JSONFile.load(TeamConfig.self, from: url) else { return }
        team = cfg
        save()
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "team.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        JSONFile.save(team, to: url)
    }

}

/// Account connection status with the one action that matters right now.
private struct ConnectionRow: View {
    let account: AccountConfig
    let signIn: () -> Void
    @ObservedObject var state = AppState.shared
    @ObservedObject var center = SignInCenter.shared

    var body: some View {
        if center.isWaiting(account.id) {
            SignInWaitingView(accountID: account.id, email: account.email).padding(.vertical, 4)
        } else {
            status
        }
    }

    private var status: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error = center.errors[account.id] { Text(error).font(.callout).foregroundStyle(.red) }
            }
            Spacer(minLength: 12)
            if state.checking.contains(account.id) { ProgressView().controlSize(.small) }
            if let wrong {
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Sign In Again…", action: signIn).buttonStyle(.borderedProminent).controlSize(.large)
                    Button("Use \(wrong)") { SignInCenter.shared.acceptSignedInAddress(account.id) }
                        .buttonStyle(.borderless).font(.callout)
                }
            } else if needsSignIn {
                Button(expired ? "Sign In Again…" : "Sign In…", action: signIn)
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button("Check Now") { Task { await Poller.shared.poll(account) } }
                    .disabled(!account.enabled || state.checking.contains(account.id))
            }
        }
        .padding(.vertical, 4)
    }

    private var expired: Bool { state.expired.contains(account.id) }
    private var wrong: String? { state.wrongAccount[account.id] }
    private var needsSignIn: Bool { state.needsSignIn(account.id) }
    private var problems: Int { state.errorCount(for: account.id) }
    private var lastChecked: Date? { ItemSource.allCases.compactMap { state.status(account.id, $0).lastChecked }.max() }

    private var symbol: String {
        if expired || wrong != nil { return "exclamationmark.triangle.fill" }
        if needsSignIn { return "person.crop.circle.badge.questionmark" }
        return problems > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
    }
    private var color: Color {
        if expired || wrong != nil { return .orange }
        if needsSignIn { return .secondary }
        return problems > 0 ? .orange : .green
    }
    private var title: String {
        if wrong != nil { return "Signed In as a Different Account" }
        if expired { return "Sign-in Expired" }
        if needsSignIn { return "Not Signed In" }
        return problems > 0 ? "Connected, \(problems) service\(problems == 1 ? "" : "s") need\(problems == 1 ? "s" : "") attention" : "Connected"
    }
    private var subtitle: String {
        let provider = account.provider == .google ? "Google" : "Microsoft"
        if let wrong { return "You signed in as \(wrong), but this account is \(account.email). Nothing is being checked until this is fixed." }
        if expired { return "\(provider) ended this sign-in. Sign in again to resume checking \(account.email)." }
        if needsSignIn { return "Sign in with \(provider) to start checking \(account.email)." }
        if !account.enabled { return "Checking is turned off for this account." }
        if let t = lastChecked { return "Last checked \(t.formatted(.relative(presentation: .named)))." }
        return "Waiting for the first check."
    }
}

/// The macOS sidebar material (translucent, follows light/dark and the desktop tint).
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
