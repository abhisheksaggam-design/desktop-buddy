import SwiftUI
import AppKit

/// Tracks browser sign-ins per account so every screen shows the same state and can
/// cancel, reopen or copy the link (for when the browser opens in the wrong profile).
@MainActor
final class SignInCenter: ObservableObject {
    static let shared = SignInCenter()

    /// accountID -> sign-in link (nil until the link is ready)
    @Published private(set) var waiting: [String: URL?] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var copied: String?
    private var attempt: [String: Int] = [:]

    func isWaiting(_ id: String) -> Bool { waiting[id] != nil }
    func link(_ id: String) -> URL? { waiting[id] ?? nil }

    /// Starts (or restarts) sign-in. Returns true when the account is signed in.
    @discardableResult
    func start(_ account: AccountConfig) async -> Bool {
        let n = (attempt[account.id] ?? 0) + 1
        attempt[account.id] = n
        errors[account.id] = nil
        waiting[account.id] = .some(nil)
        do {
            try await OAuth.shared.signIn(account) { [weak self] url in
                guard self?.attempt[account.id] == n else { return }
                self?.waiting[account.id] = .some(url)
            }
            guard attempt[account.id] == n else { return false }
            waiting[account.id] = nil
            let state = AppState.shared
            state.expired.remove(account.id)
            state.wrongAccount[account.id] = nil
            // Catch the "approved in the wrong browser profile" case before showing anyone's mail.
            // A brand-new account has no email yet: whoever signs in is the account being added.
            if !account.email.isEmpty, let emails = try? await OAuth.signedInEmails(account), !emails.isEmpty,
               !emails.contains(account.email.lowercased()) {
                state.wrongAccount[account.id] = emails[0]
                state.refreshSignedIn()
                return false
            }
            state.refreshSignedIn()
            return true
        } catch {
            // A newer attempt replaced this one: leave its state alone.
            guard attempt[account.id] == n else { return false }
            waiting[account.id] = nil
            if case AuthError.cancelled = error { return false }
            errors[account.id] = error.localizedDescription
            return false
        }
    }

    func cancel(_ id: String) {
        attempt[id] = (attempt[id] ?? 0) + 1
        waiting[id] = nil
        Task { await OAuth.shared.cancelSignIn(id) }
    }

    func reopen(_ id: String) {
        if let url = link(id) { NSWorkspace.shared.open(url) }
    }

    func copyLink(_ id: String) {
        guard let url = link(id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        copied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.copied == id { self?.copied = nil }
        }
    }

    func clearError(_ id: String) { errors[id] = nil }

    /// Keep the sign-in but switch the account to the address that actually signed in.
    func acceptSignedInAddress(_ id: String) {
        let state = AppState.shared
        guard let actual = state.wrongAccount[id], var a = state.account(id) else { return }
        a.email = actual
        state.update(a)
        state.wrongAccount[id] = nil
        Task { await Poller.shared.poll(a) }
    }
}

/// Shown while waiting for the browser: what to do, plus Cancel / Open Again / Copy Link.
struct SignInWaitingView: View {
    let accountID: String
    let email: String
    var compact = false
    @ObservedObject var center = SignInCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish signing in in your browser").font(.headline)
                    Text(email.isEmpty
                         ? "Choose the account you want to add and allow access. This updates by itself when you're done."
                         : "Sign in as \(email) and allow access. This updates by itself when you're done.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Button("Cancel") { center.cancel(accountID) }
                Spacer()
                Button(center.copied == accountID ? "Copied" : "Copy Sign-in Link") { center.copyLink(accountID) }
                    .disabled(center.link(accountID) == nil)
                    .help("Paste this link into the browser profile signed in as \(email)")
                Button("Open Again") { center.reopen(accountID) }
                    .disabled(center.link(accountID) == nil)
            }
            if !compact {
                Label(email.isEmpty
                      ? "Opened in the wrong browser profile? Copy the link and paste it into the profile you use for this account."
                      : "Opened in the wrong browser profile? Copy the link and paste it into the profile signed in as \(email).",
                      systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
