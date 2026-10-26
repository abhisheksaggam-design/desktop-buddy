import SwiftUI
import AppKit

// MARK: - Sidebar row

struct ClientSidebarRow: View {
    let client: ClientConfig
    @ObservedObject var state = AppState.shared
    var body: some View {
        HStack(spacing: 8) {
            LogoTile(url: state.ownerLogoURL(client.id), name: client.name, tint: client.tint.color, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(client.name).lineLimit(1)
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if client.enabled && !state.clientIssues(client).isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            let n = state.items.filter { $0.clientID == client.id }.count
            if n > 0 {
                Text("\(n)").font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            }
        }
        .opacity(client.enabled ? 1 : 0.55)
    }
    private var summary: String {
        if !client.enabled { return "Off" }
        if !state.clientIssues(client).isEmpty { return "Needs attention" }
        var parts: [String] = []
        if !client.senders.isEmpty { parts.append("\(client.senders.count) sender\(client.senders.count == 1 ? "" : "s")") }
        if !client.keywords.isEmpty { parts.append("\(client.keywords.count) keyword\(client.keywords.count == 1 ? "" : "s")") }
        if !client.chats.isEmpty { parts.append("\(client.chats.count) chat\(client.chats.count == 1 ? "" : "s")") }
        return parts.isEmpty ? "No rules yet" : parts.joined(separator: " · ")
    }
}

// MARK: - Client detail

struct ClientDetailView: View {
    let clientID: String
    @ObservedObject var state = AppState.shared
    @Local private var confirmRemove = false
    @Local private var pickingChats = false

    private var binding: Binding<ClientConfig> {
        Binding(get: { state.client(clientID) ?? ClientConfig(name: "") },
                set: { state.updateClient($0) })
    }

    var body: some View {
        let c = binding.wrappedValue
        Form {
            Section {
                HStack(spacing: 14) {
                    LogoTile(url: state.ownerLogoURL(c.id), name: c.name, tint: c.tint.color, size: 64)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.name.isEmpty ? "Client" : c.name).font(.title2.weight(.semibold))
                        Text(scopeText(c)).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(waiting == 0 ? "No notifications right now"
                                 : "\(waiting) notification\(waiting == 1 ? "" : "s") on your screen")
                                .font(.callout).foregroundStyle(.secondary)
                            if waiting > 0 {
                                Button("Show") {
                                    state.filterOwner = c.id
                                    state.expanded = true
                                }
                                .buttonStyle(.link).font(.callout)
                            }
                        }
                        HStack(spacing: 8) {
                            Button("Change Logo…") { pickLogo() }.controlSize(.small)
                            if c.logoPath != nil {
                                Button("Use Default") { var x = c; x.logoPath = nil; state.updateClient(x) }.controlSize(.small)
                            }
                        }
                    }
                    Spacer()
                    Toggle("Client on", isOn: binding.enabled).toggleStyle(.switch).labelsHidden()
                        .help(c.enabled ? "Turn off to stop sorting items into this client" : "Turn on")
                }
                .padding(.vertical, 4)
            }

            let issues = state.clientIssues(c)
            if !issues.isEmpty {
                Section {
                    IssueList(issues: issues, clientID: c.id)
                } header: {
                    Text("Needs Attention")
                }
            }

            Section {
                TokenField(title: "Senders", prompt: "Type a domain or address, e.g. gatehouse.co.uk",
                           hint: "A whole domain (gatehouse.co.uk) or one person (jane@gatehouse.co.uk). Press Return to add.",
                           tokens: binding.senders, symbol: "at", tint: .blue, validate: TokenField.senderProblem)
                TokenField(title: "Keywords", prompt: "Type a word to look for, e.g. invoice",
                           hint: "Matched as a whole word in the subject or preview, so “FEMA” won't match “female”.",
                           tokens: binding.keywords, symbol: "text.magnifyingglass", tint: .purple, validate: TokenField.keywordProblem)
            } header: {
                Text("Email")
            } footer: {
                Footnote("New unread inbox mail that comes from a sender above, or contains a keyword, shows under \(c.name.isEmpty ? "this client" : c.name). Mail you've already read or filed away never interrupts you.")
            }

            Section {
                if c.chats.isEmpty {
                    Text("No chats picked").foregroundStyle(.secondary)
                }
                ForEach(c.chats) { chat in
                    let problem = state.clientIssues(c).first { $0.chat == chat }
                    HStack(spacing: 8) {
                        if let a = state.account(chat.accountID) { AccountMark(account: a, size: 18) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(chat.name)
                            if let problem {
                                Label("Not being checked", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange)
                                    .help(problem.text)
                            } else {
                                Text("\(chatKind(chat)) · \(state.account(chat.accountID)?.label ?? "") · being checked")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let problem, let fix = problem.fix, let label = problem.fixLabel {
                            Spacer()
                            Button(label) { withAnimation(buddySpring) { state.apply(fix, client: c.id) } }.controlSize(.small)
                        }
                        Spacer()
                        Button { var x = c; x.chats.removeAll { $0 == chat }; state.updateClient(x) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless).accessibilityLabel("Remove \(chat.name)")
                    }
                }
                Button { pickingChats = true } label: { Label("Add Chats…", systemImage: "plus") }
                    .disabled(state.config.accounts.filter { state.signedIn.contains($0.id) }.isEmpty)
                Toggle(isOn: binding.matchChatNames) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Also match chats named after \(c.name)")
                        Text("Spaces and group chats whose name includes “\(c.name)”, and direct messages with someone of that name.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Google Chat & Teams")
            } footer: {
                Footnote("Pick the Google Chat spaces and Teams chats you share with this client. New messages there show under the client's logo instead of the account's.")
            }

            Section {
                Picker("Look in", selection: Binding(
                    get: { c.accountIDs.isEmpty ? "all" : "some" },
                    set: { v in var x = c; x.accountIDs = v == "all" ? [] : state.config.accounts.map(\.id); state.updateClient(x) })) {
                    Text("All accounts").tag("all")
                    Text("Selected accounts").tag("some")
                }
                if !c.accountIDs.isEmpty {
                    ForEach(state.config.accounts) { a in
                        Toggle(isOn: Binding(
                            get: { c.accountIDs.contains(a.id) },
                            set: { on in
                                var x = c
                                if on { x.accountIDs.append(a.id) } else { x.accountIDs.removeAll { $0 == a.id } }
                                state.updateClient(x)
                            })) {
                            HStack(spacing: 6) { AccountMark(account: a, size: 16); Text(a.label) }
                        }
                        // Keep at least one account selected (otherwise it would silently mean "all").
                        .disabled(c.accountIDs == [a.id])
                    }
                }
            } header: {
                Text("Accounts")
            }

            Section("Appearance") {
                TextField("Name", text: binding.name)
                LabeledContent("Color") { TintPicker(selection: binding.tint) }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Remove Client…", role: .destructive) { confirmRemove = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(c.name)
        .sheet(isPresented: $pickingChats) {
            ChatPickerSheet(selected: c.chats, clientName: c.name) { picked in
                var x = c; x.chats = picked; state.updateClient(x)
            }
        }
        .confirmationDialog("Remove \(c.name)?", isPresented: $confirmRemove) {
            Button("Remove Client", role: .destructive) {
                SettingsRouter.shared.selection = .general
                state.removeClient(c.id)
            }
        } message: {
            Text("Its mails and chats will show under their accounts again.")
        }
    }

    private var waiting: Int { state.items.filter { $0.clientID == clientID }.count }

    private func chatKind(_ c: ChatRef) -> String {
        c.kind == .direct ? "Direct message" : (c.kind == .group ? "Group chat" : (c.kind == .space ? "Space" : "Chat"))
    }

    private func scopeText(_ c: ClientConfig) -> String {
        let names = c.accountIDs.compactMap { state.account($0)?.label }
        if c.accountIDs.isEmpty || names.count == state.config.accounts.count { return "Client · watching all your accounts" }
        return "Client · watching \(ListFormatter.localizedString(byJoining: names))"
    }

    private func pickLogo() {
        guard let src = Logos.choose(), var x = state.client(clientID),
              let path = Logos.importImage(from: src, as: "client") else { return }
        x.logoPath = path
        state.updateClient(x)
    }
}

// MARK: - Token field (chips)

/// Mail-style token field: existing entries show as chips inside the field, followed by the
/// place to type. Return or a comma adds; ✕ on a chip (or Delete on an empty field) removes.
struct TokenField: View {
    let title: String
    let prompt: String
    let hint: String
    @Binding var tokens: [String]
    var symbol: String
    var tint: Color
    /// Returns a message when an entry can't work; it isn't added and the message is shown.
    var validate: (String) -> String? = { _ in nil }
    @Local private var draft = ""
    @Local private var problem: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SettingsIcon(symbol: symbol, tint: tint, size: 20)
                Text(title)
                Spacer()
                Text(tokens.isEmpty ? "None yet" : "\(tokens.count) added")
                    .font(.callout).foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 6) {
                ForEach(tokens, id: \.self) { t in
                    HStack(spacing: 4) {
                        Text(t).font(.callout)
                        Button { tokens.removeAll { $0 == t } } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .accessibilityLabel("Remove \(t)")
                    }
                    .padding(.leading, 9).padding(.trailing, 7).frame(height: 24)
                    .background(Capsule().fill(tint.opacity(0.15)))
                }
                TextField(title, text: $draft, prompt: Text(tokens.isEmpty ? prompt : "Add another…"))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .focused($focused)
                    .frame(minWidth: 180)
                    .frame(height: 24)
                    .onSubmit(add)
                    .onChange(of: draft) { _, v in if v.contains(",") { add() } }
                    .onKeyPress(.delete) {
                        guard draft.isEmpty, !tokens.isEmpty else { return .ignored }
                        tokens.removeLast(); return .handled
                    }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(focused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: focused ? 2 : 1))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func add() {
        let parts = draft.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let bad = parts.compactMap { p in validate(p).map { (p, $0) } }
        tokens = Self.merge(parts.filter { p in !bad.contains { $0.0 == p } }.joined(separator: ","), into: tokens)
        if let (p, msg) = bad.first {
            problem = msg
            draft = p                     // keep what they typed so it can be corrected
        } else {
            problem = nil
            draft = ""
        }
    }

    /// Senders must be a domain (has a dot) or a full address.
    static func senderProblem(_ s: String) -> String? {
        let v = s.trimmingCharacters(in: CharacterSet(charactersIn: " @"))
        if v.contains(" ") { return "“\(s)” has a space. Use a domain like gatehouse.co.uk or an address like jane@gatehouse.co.uk." }
        if v.contains("@") {
            let parts = v.split(separator: "@")
            return parts.count == 2 && parts[1].contains(".") ? nil : "“\(s)” isn't a complete email address."
        }
        return v.contains(".") ? nil : "“\(s)” isn't a domain. Add the ending, e.g. \(v).co.uk or \(v).com."
    }

    static func keywordProblem(_ s: String) -> String? {
        s.count < 3 ? "“\(s)” is too short to be useful. Use at least 3 letters." : nil
    }

    /// Accepts comma-separated input; trims, drops empties and case-insensitive duplicates.
    static func merge(_ input: String, into tokens: [String]) -> [String] {
        var out = tokens
        for t in input.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !t.isEmpty {
            if !out.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { out.append(t) }
        }
        return out
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); widest = max(widest, x)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Chat picker

struct ChatPickerSheet: View {
    let clientName: String
    let onDone: ([ChatRef]) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state = AppState.shared
    @Local private var picked: Set<ChatRef>
    @Local private var all: [ChatRef] = []
    @Local private var loading = true
    @Local private var errors: [String] = []
    @Local private var search = ""
    @Local private var namesDone = 0
    @Local private var namesTotal = 0

    init(selected: [ChatRef], clientName: String, onDone: @escaping ([ChatRef]) -> Void) {
        self.clientName = clientName
        self.onDone = onDone
        _picked = Local(wrappedValue: Set(selected))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chats for \(clientName)").font(.title3.weight(.semibold))
                    Text("Google Chat spaces and Teams chats you're in").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding([.horizontal, .top], 20).padding(.bottom, 10)
            TextField("Search", text: $search, prompt: Text("Search chats"))
                .textFieldStyle(.roundedBorder).padding(.horizontal, 20).padding(.bottom, 8)

            List {
                if loading {
                    HStack(spacing: 10) {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Text(namesTotal > 0 ? "Finding names for direct messages… \(namesDone) of \(namesTotal)" : "Loading your chats…")
                            .foregroundStyle(.secondary).monospacedDigit()
                        Spacer()
                    }
                    .padding()
                }
                ForEach(errors, id: \.self) { e in
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                }
                ForEach(groups, id: \.0) { accountID, chats in
                    Section {
                        if let a = state.account(accountID), let b = state.blocker(a, .chat) {
                            HStack {
                                Label("\(b.0). Chats you pick here won't be checked until it's on.",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.callout).foregroundStyle(.orange)
                                Spacer()
                                if case .turnOnService = b.1 {
                                    Button(b.2) { state.apply(b.1, client: "") }.controlSize(.small)
                                }
                            }
                        }
                        ForEach(chats) { chat in
                            Toggle(isOn: Binding(get: { picked.contains(chat) },
                                                 set: { on in if on { picked.insert(chat) } else { picked.remove(chat) } })) {
                                HStack(spacing: 8) {
                                    Image(systemName: chat.kind == .direct ? "person.fill" : (chat.kind == .group ? "person.2.fill" : "number"))
                                        .foregroundStyle(.secondary).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(chat.name).lineLimit(1)
                                        Text(subtitle(chat)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if chat.name.localizedCaseInsensitiveContains(clientName), !clientName.isEmpty {
                                        Text("Suggested").font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            if let a = state.account(accountID) { ProviderBadge(provider: a.provider, size: 14); Text(a.label) }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: 340)

            HStack {
                Text("\(picked.count) selected").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Done") { onDone(Array(picked).sorted { $0.name < $1.name }); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480)
        .task { await load() }
    }

    private var groups: [(String, [ChatRef])] {
        let filtered = all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        let ids = state.config.accounts.map(\.id)
        return ids.compactMap { id in
            let chats = filtered.filter { $0.accountID == id }
                .sorted { a, b in
                    let sa = !clientName.isEmpty && a.name.localizedCaseInsensitiveContains(clientName)
                    let sb = !clientName.isEmpty && b.name.localizedCaseInsensitiveContains(clientName)
                    if sa != sb { return sa }
                    return (a.lastActive ?? .distantPast) > (b.lastActive ?? .distantPast)
                }
            return chats.isEmpty ? nil : (id, chats)
        }
    }

    private func subtitle(_ c: ChatRef) -> String {
        let kind = c.kind == .direct ? "Direct message" : (c.kind == .group ? "Group chat" : "Space")
        guard let t = c.lastActive else { return kind }
        return "\(kind) · active \(shortAgo(t) == "now" ? "just now" : shortAgo(t) + " ago")"
    }

    private func load() async {
        for a in state.config.accounts where a.enabled && state.signedIn.contains(a.id) {
            do {
                all += try await ChatDirectory.list(a) { done, total in namesDone = done; namesTotal = total }
            }
            catch { errors.append("\(a.label): \(error.localizedDescription)") }
        }
        loading = false
    }
}

// MARK: - Add client

struct AddClientSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state = AppState.shared
    private var duplicateName: Bool {
        let n = draft.name.trimmingCharacters(in: .whitespaces)
        return !n.isEmpty && state.config.clients.contains { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }
    @Local private var draft = ClientConfig(name: "")
    @Local private var addNameKeyword = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                LogoTile(url: draft.logoPath.map { URL(fileURLWithPath: $0) } ?? Logos.url(path: nil, name: draft.name),
                         name: draft.name.isEmpty ? "?" : draft.name, tint: draft.tint.color, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Add Client").font(.title3.weight(.semibold))
                    Text("For clients who email or chat with you but don't give you an account.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding([.horizontal, .top], 20).padding(.bottom, 6)
            Form {
                TextField("Name", text: $draft.name, prompt: Text("e.g. Gatehouse"))
                LabeledContent("Logo") {
                    Button(draft.logoPath == nil ? "Choose…" : "Change…") {
                        if let src = Logos.choose() { draft.logoPath = Logos.importImage(from: src, as: "client") }
                    }
                }
                LabeledContent("Color") { TintPicker(selection: $draft.tint) }
                Toggle("Also sort emails that mention “\(draft.name.isEmpty ? "the name" : draft.name)”", isOn: $addNameKeyword)
                if duplicateName {
                    Label("You already have a client called \(draft.name).", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)
            .frame(height: 230)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Client") {
                    var c = draft
                    c.name = c.name.trimmingCharacters(in: .whitespaces)
                    if addNameKeyword { c.keywords = [c.name] }
                    state.addClient(c)
                    SettingsRouter.shared.selection = .client(c.id)
                    dismiss()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || duplicateName)
            }
            .padding(16)
        }
        .frame(width: 480)
    }
}
