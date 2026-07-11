//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Stores the GitHub Personal Access Token (in the Keychain) used to import a repository's issues
/// into a plan — see ``GitHubImportService``. The token never leaves the Keychain.
struct GitHubSettingsTab: View {

    @State private var token: String = ""
    @State private var status: VerifyStatus = .idle

    private enum VerifyStatus: Equatable {
        case idle
        case verifying
        case success(String)
        case failure(String)
    }

    private static let tokenHelpURL = URL(string: "https://github.com/settings/tokens?type=beta")!

    var body: some View {
        Form {
            Section {
                LabeledContent("Token:") {
                    SecureField("ghp_… or github_pat_…", text: $token)
                        .labelsHidden()
                        .frame(minWidth: 240)
                        .onSubmit(verify)
                }

                HStack {
                    Button("Verify & Save", action: verify)
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || status == .verifying)
                    Button("Remove", role: .destructive, action: removeToken)
                        .disabled(token.isEmpty && !Keychain.hasGitHubToken)
                    if status == .verifying { ProgressView().controlSize(.small) }
                }

                statusRow
            } header: {
                Text("Personal Access Token")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Used to read issues when importing a repository. Grant a fine-grained token read-only access to **Issues** (and **Contents**/**Metadata** for private repos).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Create a token on GitHub →", destination: Self.tokenHelpURL)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460, height: 280)
        .onAppear {
            token = Keychain.get(account: Keychain.Account.githubToken) ?? ""
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch status {
        case .idle:
            if Keychain.hasGitHubToken {
                Label("A token is saved.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        case .verifying:
            EmptyView()
        case .success(let login):
            Label("Verified as \(login).", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private func verify() {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Keychain.set(trimmed, account: Keychain.Account.githubToken)
        status = .verifying
        Task {
            do {
                let login = try await GitHubClient(token: trimmed).verify()
                status = .success(login)
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }

    private func removeToken() {
        Keychain.delete(account: Keychain.Account.githubToken)
        token = ""
        status = .idle
    }
}

private extension Keychain {
    /// Whether a GitHub token is currently stored (for enabling UI without exposing the value).
    static var hasGitHubToken: Bool {
        Keychain.get(account: Account.githubToken)?.isEmpty == false
    }
}

#Preview {
    GitHubSettingsTab()
}
