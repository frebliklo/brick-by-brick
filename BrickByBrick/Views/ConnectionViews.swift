import SwiftUI

// MARK: - Shared pieces

/// A big, friendly status mark at the top of a connection page.
struct ConnectionHero: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: Text
    var tint: Color = Palette.orange
    var tintBackground: Color = Palette.orangeTint

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 96, height: 96)
                .background(tintBackground, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            message.font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.top, 12)
    }
}

/// A rounded white card that groups controls on connection pages.
struct ConnectionCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}

/// A soft rounded text field that matches the app's search field.
struct SoftTextField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    var secure = false
    var identifier: String
    var body: some View {
        Group {
            if secure { SecureField(prompt, text: $text) } else { TextField(prompt, text: $text) }
        }
        .font(.system(.body, design: .rounded, weight: .medium))
        .autocorrectionDisabled().disableMobileAutocapitalization()
        .padding(.horizontal, 16).frame(minHeight: 52)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
        .accessibilityIdentifier(identifier)
    }
}

/// A Settings row that opens a connection page; the status sits under the title so it never truncates.
struct ConnectionRow: View {
    let title: LocalizedStringKey
    let status: Text
    let connected: Bool
    let systemImage: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage).font(.title3)
                .foregroundStyle(connected ? Palette.green : Palette.orange)
                .frame(width: 42, height: 42)
                .background(connected ? Palette.greenTint : Palette.orangeTint, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                HStack(spacing: 5) {
                    Image(systemName: connected ? "checkmark.circle.fill" : "circle.dashed")
                    status
                }
                .font(.subheadline.weight(connected ? .semibold : .regular))
                .foregroundStyle(connected ? Palette.green : Palette.muted)
            }
        }.padding(.vertical, 4)
    }
}

private struct StepRow<Accessory: View>: View {
    let number: Int
    let title: LocalizedStringKey
    @ViewBuilder let accessory: Accessory
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(verbatim: "\(number)")
                .font(.system(.headline, design: .rounded, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(Palette.orange, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
            }
        }
    }
}

// MARK: - Catalog (API key)

struct CatalogConnectionView: View {
    @Environment(AppStore.self) private var store
    @State private var key = ""
    @State private var message: String?
    @State private var validating = false
    @State private var replacing = false
    @State private var confirmDisconnect = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if store.isConnected { connected } else { setup }
            }.padding(24).pageWidth(640)
        }
        .background(Palette.background)
        .navigationTitle("LEGO catalog").inlineNavigationTitle()
        .task(id: validating) {
            guard validating else { return }
            defer { validating = false }
            do {
                let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await CatalogClient(apiKey: cleaned).search("31124")
                try Task.checkCancellation()
                try store.saveKey(cleaned)
                key = ""; replacing = false; message = nil
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
        .confirmationDialog("Disconnect the catalog? Your saved checklists will stay on this device.", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                do { try store.saveKey(""); message = nil; key = "" }
                catch { message = error.localizedDescription }
            }
        }
    }

    private var setup: some View {
        Group {
            ConnectionHero(systemImage: "magnifyingglass",
                           title: "Connect the LEGO catalog",
                           message: Text("A free Rebrickable key lets you search every LEGO set and get its full list of bricks."))
            ConnectionCard {
                StepRow(number: 1, title: "Make a free Rebrickable account") {
                    Link(destination: URL(string: "https://rebrickable.com/register/")!) {
                        Label("Open Rebrickable", systemImage: "arrow.up.right")
                    }.font(.subheadline.weight(.semibold))
                }
                StepRow(number: 2, title: "Copy your key from the API page") {
                    Link(destination: URL(string: "https://rebrickable.com/api/")!) {
                        Label("Open the API page", systemImage: "arrow.up.right")
                    }.font(.subheadline.weight(.semibold))
                }
                StepRow(number: 3, title: "Paste it here") {
                    keyField
                }
            }
            connectButton(title: "Connect catalog")
            footnote
        }
    }

    private var connected: some View {
        Group {
            ConnectionHero(systemImage: "checkmark", title: "Catalog connected",
                           message: Text("You can search every LEGO set and download its bricks."),
                           tint: Palette.green, tintBackground: Palette.greenTint)
            ConnectionCard {
                if replacing {
                    Text("Paste a new key").font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    keyField
                    connectButton(title: "Check and save key")
                    Button("Cancel") { replacing = false; key = ""; message = nil }
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                } else {
                    Button { replacing = true } label: {
                        Label("Use a different key", systemImage: "key")
                            .font(.body.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).foregroundStyle(Palette.orange)
                }
            }
            if let message, replacing { InlineMessage(text: Text(verbatim: message)) }
            footnote
            Button("Disconnect catalog", role: .destructive) { confirmDisconnect = true }
                .font(.subheadline.weight(.semibold)).padding(.top, 8)
        }
    }

    private var keyField: some View {
        SoftTextField(prompt: "API key", text: $key, secure: true, identifier: "apiKeyInput")
            .textContentType(.password)
    }

    private func connectButton(title: LocalizedStringKey) -> some View {
        VStack(spacing: 12) {
            if let message, !store.isConnected { InlineMessage(text: Text(verbatim: message)) }
            Button { validating = true } label: {
                if validating { HStack { ProgressView().tint(.white); Text("Checking your key…") } }
                else { Text(title) }
            }
            .buttonStyle(PrimaryButton())
            .disabled(validating || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
    }

    private var footnote: some View {
        Label("Your key stays in this device’s Keychain and is only sent to Rebrickable.", systemImage: "lock")
            .font(.caption).foregroundStyle(Palette.muted)
    }
}

// MARK: - Rebrickable account (user token)

struct RebrickableAccountView: View {
    @Environment(AppStore.self) private var store
    @State private var username = ""
    @State private var password = ""
    @State private var signingIn = false
    @State private var message: String?
    @State private var showSets = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if !store.isConnected { needsCatalog }
                else if store.isSignedIn { signedIn }
                else { signIn }
            }.padding(24).pageWidth(640)
        }
        .background(Palette.background)
        .navigationTitle("Rebrickable sets").inlineNavigationTitle()
        .navigationDestination(isPresented: $showSets) { RebrickableSetsView() }
        .task(id: signingIn) {
            guard signingIn else { return }
            defer { signingIn = false }
            do {
                let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
                let token = try await store.client.signIn(username: name, password: password)
                try Task.checkCancellation()
                try store.saveSignIn(username: name, token: token)
                password = ""; message = nil
                showSets = true
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }

    private var needsCatalog: some View {
        Group {
            ConnectionHero(systemImage: "shippingbox", title: "Bring in the sets you own",
                           message: Text("Connect the LEGO catalog first. Then you can sign in to Rebrickable here."))
            NavigationLink { CatalogConnectionView() } label: { Text("Connect the catalog") }
                .buttonStyle(PrimaryButton())
        }
    }

    private var signIn: some View {
        Group {
            ConnectionHero(systemImage: "shippingbox", title: "Bring in the sets you own",
                           message: Text("Sign in to Rebrickable to see your set collection and add sets here in one go."))
            ConnectionCard {
                benefit("square.stack.3d.up", "See every set in your Rebrickable collection")
                benefit("checklist", "Pick the ones to build again")
                benefit("lock", "Your password is never saved, only a sign-in token")
            }
            ConnectionCard {
                SoftTextField(prompt: "Username or email", text: $username, identifier: "rebrickableUsername")
                    .textContentType(.username)
                SoftTextField(prompt: "Password", text: $password, secure: true, identifier: "rebrickablePassword")
                    .textContentType(.password)
                if let message { InlineMessage(text: Text(verbatim: message)) }
                Button { signingIn = true } label: {
                    if signingIn { HStack { ProgressView().tint(.white); Text("Signing in…") } }
                    else { Text("Sign in") }
                }
                .buttonStyle(PrimaryButton())
                .disabled(!canSignIn || signingIn)
                .opacity(canSignIn ? 1 : 0.5)
            }
            Text("Signed up with Google or Facebook? Set a password on Rebrickable first.")
                .font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
    }

    private var canSignIn: Bool { !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty }

    private var signedIn: some View {
        Group {
            ConnectionHero(systemImage: "person.crop.circle.badge.checkmark",
                           title: "Signed in as \(store.rebrickableUsername)",
                           message: Text("Your Rebrickable collection is ready to browse."),
                           tint: Palette.green, tintBackground: Palette.greenTint)
            Button { showSets = true } label: { Label("See my Rebrickable sets", systemImage: "square.stack.3d.up") }
                .buttonStyle(PrimaryButton()).accessibilityIdentifier("importRebrickableSets")
            if let message { InlineMessage(text: Text(verbatim: message)) }
            Button("Sign out of Rebrickable", role: .destructive) {
                do { try store.signOut(); message = nil } catch { message = error.localizedDescription }
            }.font(.subheadline.weight(.semibold)).padding(.top, 8)
        }
    }

    private func benefit(_ icon: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text).foregroundStyle(Palette.ink) } icon: {
            Image(systemName: icon).foregroundStyle(Palette.green)
        }.font(.subheadline)
    }
}
