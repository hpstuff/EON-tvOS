import SwiftUI

/// Sign-in with either a password or a one-time code. The SDK registers this Apple TV with the
/// platform on first use, hashes the username and exchanges credentials for tokens; this
/// screen collects input, shows the code and reports the outcome.
struct SignInView: View {
  @Environment(AppSession.self) private var session

  @State private var mode: Mode = .password
  @State private var username = ""
  @State private var password = ""
  @FocusState private var focus: Field?

  private enum Mode: Hashable {
    case password, code
  }

  private enum Field: Hashable {
    case modePassword, modeCode, username, password, submit, newCode
  }

  var body: some View {
    ZStack {
      AmbientBackdrop(url: nil)

      HStack(spacing: 0) {
        brandPanel
          .frame(maxWidth: .infinity, alignment: .leading)

        form
          .frame(width: 720)
      }
      .padding(.horizontal, Theme.screenMargin + 40)
    }
    .onAppear { if focus == nil { focus = .username } }
    .onChange(of: mode) { _, mode in
      switch mode {
      case .password:
        session.cancelCodeSignIn()
        focus = .username
      case .code:
        session.startCodeSignIn()
        focus = .modeCode
      }
    }
    .onDisappear { session.cancelCodeSignIn() }
  }

  private var brandPanel: some View {
    VStack(alignment: .leading, spacing: 34) {
      BrandMark(height: 120)
      VStack(alignment: .leading, spacing: 14) {
        Text("Live TV, the guide and\nseven days of catch-up.")
          .font(.system(size: 44, weight: .light))
          .foregroundStyle(Theme.textPrimary)
          .lineSpacing(4)
        Text("Sign in with your EON account to start watching.")
          .font(.system(size: 27))
          .foregroundStyle(Theme.textSecondary)
      }
    }
  }

  private var form: some View {
    VStack(alignment: .leading, spacing: 26) {
      Text("Sign In")
        .font(.system(size: 40, weight: .regular))
        .foregroundStyle(Theme.textPrimary)

      modePicker

      switch mode {
      case .password:
        passwordForm
      case .code:
        codeForm
      }

      #if DEBUG
      Button("Explore the demo") {
        session.boot(demo: true)
      }
      .buttonStyle(.pill)
      .padding(.top, 8)
      #endif
    }
    .padding(48)
    .background {
      RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        .fill(Theme.surface)
        .overlay {
          RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
            .strokeBorder(Theme.stroke, lineWidth: 1)
        }
    }
    .animation(Theme.crossfade, value: session.signInError)
    .animation(Theme.crossfade, value: mode)
    .animation(Theme.crossfade, value: session.codeSignIn)
  }

  private var modePicker: some View {
    HStack(spacing: 14) {
      Button("Password") { mode = .password }
        .buttonStyle(mode == .password ? .prominentPill : .pill)
        .focused($focus, equals: .modePassword)
      Button("Code") { mode = .code }
        .buttonStyle(mode == .code ? .prominentPill : .pill)
        .focused($focus, equals: .modeCode)
    }
  }

  // MARK: Password

  private var passwordForm: some View {
    Group {
      field(title: "Username", isFocused: focus == .username) {
        TextField("Email or phone", text: $username)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.emailAddress)
          .focused($focus, equals: .username)
          .onSubmit { focus = .password }
      }

      field(title: "Password", isFocused: focus == .password) {
        SecureField("Password", text: $password)
          .textContentType(.password)
          .focused($focus, equals: .password)
          .onSubmit { focus = .submit }
      }

      if let error = session.signInError {
        errorLabel(error)
      }

      Button {
        Task { await session.signIn(username: username, password: password) }
      } label: {
        HStack(spacing: 14) {
          if session.isSigningIn {
            ProgressView().tint(Theme.textOnFocus)
          }
          Text(session.isSigningIn ? "Signing In…" : "Sign In")
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.prominentPill)
      .disabled(session.isSigningIn)
      .focused($focus, equals: .submit)
    }
  }

  // MARK: Code

  private var codeForm: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text("On your phone or computer, sign in to EON, open Devices and enter this code to link this Apple TV.")
        .font(.system(size: 24))
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      switch session.codeSignIn {
      case .idle, .requesting:
        codePlate(nil)
        HStack(spacing: 14) {
          ProgressView().tint(Theme.textSecondary)
          Text("Getting a code…")
            .font(.system(size: 23))
            .foregroundStyle(Theme.textSecondary)
        }

      case .waiting(let code, let expiresAt):
        codePlate(code)
        HStack(spacing: 14) {
          ProgressView().tint(Theme.textSecondary)
          Text("Waiting for you to confirm the code…")
            .font(.system(size: 23))
            .foregroundStyle(Theme.textSecondary)
          Spacer()
          HStack(spacing: 6) {
            Text("Expires in")
            Text(expiresAt, style: .timer)
              .monospacedDigit()
          }
          .font(.system(size: 23, weight: .medium))
          .foregroundStyle(Theme.textTertiary)
        }

      case .expired:
        codePlate(nil)
        errorLabel("This code has expired. Get a new one to continue.")
        Button("Get a New Code") { session.startCodeSignIn() }
          .buttonStyle(.prominentPill)
          .focused($focus, equals: .newCode)

      case .failed(let message):
        codePlate(nil)
        errorLabel(message)
        Button("Try Again") { session.startCodeSignIn() }
          .buttonStyle(.prominentPill)
          .focused($focus, equals: .newCode)
      }
    }
  }

  /// The code in large, widely tracked type; a skeleton while there is none to show.
  private func codePlate(_ code: String?) -> some View {
    HStack {
      Spacer()
      if let code {
        Text(code)
          .font(.system(size: 84, weight: .light, design: .monospaced))
          .kerning(14)
          .foregroundStyle(Theme.textPrimary)
          .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
      } else {
        SkeletonBlock()
          .frame(width: 420, height: 84)
      }
      Spacer()
    }
    .padding(.vertical, 26)
    .background {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Theme.surface)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Theme.stroke, lineWidth: 1)
    }
  }

  // MARK: Pieces

  private func errorLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
      .font(.system(size: 23, weight: .medium))
      .foregroundStyle(Theme.warning)
      .transition(.opacity)
  }

  private func field<Content: View>(title: String, isFocused: Bool, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 21, weight: .medium))
        .foregroundStyle(Theme.textTertiary)
        .textCase(.uppercase)
        .kerning(1)
      content()
        .textFieldStyle(.plain)
        .font(.system(size: 28))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isFocused ? Color.white.opacity(0.22) : Theme.surface)
        }
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isFocused ? Color.white.opacity(0.85) : Theme.stroke, lineWidth: isFocused ? 2 : 1)
        }
        .animation(Theme.focusAnimation, value: isFocused)
    }
  }
}
