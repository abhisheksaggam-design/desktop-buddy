import SwiftUI

// MARK: - Mail filters (account page)

/// "Mail" and "Mute" sections on an account page: which mail notifies, and what never does.
struct MailFilterSections: View {
    @Binding var account: AccountConfig
    @Local private var picking = false

    private var word: String { account.provider == .google ? "label" : "category" }
    private var plural: String { account.provider == .google ? "labels" : "categories" }

    var body: some View {
        Section {
            Picker("Notify me about", selection: Binding(
                get: { account.labelsOnly },
                set: { var x = account; x.onlyLabelsList = $0 ? (x.onlyLabelsList ?? []) : nil; account = x })) {
                Text("All new inbox mail").tag(false)
                Text("Only mail with chosen \(plural)").tag(true)
            }
            if account.labelsOnly {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        SettingsIcon(symbol: "tag.fill", tint: .orange, size: 20)
                        Text(plural.capitalized)
                        Spacer()
                        Button("Add \(word.capitalized)…") { picking = true }
                            .controlSize(.small)
                            .popover(isPresented: $picking, arrowEdge: .trailing) {
                                LabelPicker(account: account, word: word, plural: plural) { label in
                                    var x = account
                                    if !x.onlyLabels.contains(where: { $0.id == label.id }) { x.onlyLabels.append(label) }
                                    account = x
                                }
                            }
                    }
                    if account.onlyLabels.isEmpty {
                        Label("No \(word) chosen yet, so no mail will notify you.", systemImage: "exclamationmark.circle.fill")
                            .font(.callout).foregroundStyle(.orange)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(account.onlyLabels) { l in
                                HStack(spacing: 4) {
                                    Image(systemName: "tag").font(.system(size: 9, weight: .semibold)).foregroundStyle(.orange)
                                    Text(l.name).font(.callout)
                                    Button { var x = account; x.onlyLabels.removeAll { $0.id == l.id }; account = x } label: {
                                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                    }
                                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                                    .accessibilityLabel("Remove \(l.name)")
                                }
                                .padding(.leading, 8).padding(.trailing, 7).frame(height: 24)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Mail")
        } footer: {
            Footnote(account.labelsOnly
                     ? "Only unread mail with one of these \(plural) notifies you, even if a rule moved it out of your inbox."
                     : "Unread mail that arrives in your inbox notifies you. To hear only about mail your rules \(account.provider == .google ? "label" : "categorise"), choose “Only mail with chosen \(plural)”.")
        }

        Section {
            TokenField(title: "Senders", prompt: "Type a domain or address, e.g. news.example.com",
                       hint: "A whole domain (example.com) or one address (noreply@example.com). Press Return to add.",
                       tokens: $account.mutedSenders, symbol: "speaker.slash.fill", tint: .gray,
                       validate: TokenField.senderProblem)
            TokenField(title: "Keywords", prompt: "Type a word, e.g. newsletter",
                       hint: "Matched as a whole word in the subject, preview or sender's name.",
                       tokens: $account.mutedKeywords, symbol: "text.badge.xmark", tint: .gray,
                       validate: TokenField.keywordProblem)
        } header: {
            Text("Mute")
        } footer: {
            Footnote("Muted mail never pops up, even for a client. It stays unread in \(account.provider.mailName), so you can still find it there.")
        }
    }
}

/// Popover listing the account's Gmail labels or recent Outlook categories, with search.
private struct LabelPicker: View {
    let account: AccountConfig
    let word: String
    let plural: String
    let onPick: (MailLabel) -> Void
    @Environment(\.dismiss) private var dismiss
    @Local private var all: [MailLabel] = []
    @Local private var loading = true
    @Local private var error: String? = nil
    @Local private var search = ""

    private var shown: [MailLabel] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let taken = Set(account.onlyLabels.map(\.id))
        return all.filter { !taken.contains($0.id) && (q.isEmpty || $0.name.localizedCaseInsensitiveContains(q)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search", text: $search, prompt: Text("Search \(plural)"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { if let first = shown.first { pick(first) } else { addTyped() } }
            Group {
                if loading {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading \(plural)…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                } else if shown.isEmpty && search.isEmpty {
                    Text(all.isEmpty ? "No \(plural) found." : "All your \(plural) are already chosen.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(shown) { l in
                                Button { pick(l) } label: {
                                    Label(l.name, systemImage: "tag").frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 5).padding(.horizontal, 6).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }
            // Outlook only lists categories seen on recent mail, so allow typing one in.
            if account.provider == .microsoft, !search.trimmingCharacters(in: .whitespaces).isEmpty,
               !all.contains(where: { $0.name.caseInsensitiveCompare(search.trimmingCharacters(in: .whitespaces)) == .orderedSame }) {
                Button("Add “\(search.trimmingCharacters(in: .whitespaces))”") { addTyped() }
            }
            if account.provider == .microsoft {
                Text("Shows categories used on your recent mail. Type a name to add another.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 280)
        .task { await load() }
    }

    private func pick(_ l: MailLabel) { onPick(l); dismiss() }

    private func addTyped() {
        let name = search.trimmingCharacters(in: .whitespaces)
        guard account.provider == .microsoft, !name.isEmpty else { return }
        pick(MailLabel(id: name, name: name))
    }

    private func load() async {
        let api = APIClient(account: account)
        do {
            all = account.provider == .google ? try await GmailSource.labels(api) : try await OutlookMailSource.categories(api)
        } catch {
            self.error = "Couldn't load your \(plural): \(error.localizedDescription)"
        }
        loading = false
    }
}

// MARK: - Sounds (General page)

/// One row per kind of notification: icon, name, sound menu and a play button.
struct SoundRow: View {
    let source: ItemSource
    @ObservedObject var state = AppState.shared

    var body: some View {
        let current = state.config.sound(for: source)
        HStack(spacing: 10) {
            SettingsIcon(symbol: source.symbol, tint: source.tint, size: 20)
            Picker(source.pluralName, selection: Binding(
                get: { current },
                set: { state.config.setSound($0, for: source); Sounds.play($0) })) {
                Text("None").tag(noSound)
                Divider()
                ForEach(Sounds.all, id: \.self) { Text($0).tag($0) }
            }
            Button { Sounds.play(current) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
                .disabled(current == noSound)
                .help("Play \(current)")
                .accessibilityLabel("Play the \(source.pluralName.lowercased()) sound")
        }
        .disabled(!state.config.playSound)
    }
}

extension ItemSource {
    var pluralName: String {
        switch self {
        case .mail: return "Mail"
        case .chat: return "Chats"
        case .meeting: return "Meetings"
        case .task: return "Tasks"
        case .reminder: return "Reminders"
        }
    }
}
