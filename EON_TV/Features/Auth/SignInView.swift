import SwiftUI
import EONKit

/// Sign-in with either a password or a one-time code. The SDK registers this Apple TV with the
/// platform on first use, hashes the username and exchanges credentials for tokens; this
/// screen collects input, shows the code and reports the outcome.
struct SignInView: View {
  @Environment(AppSession.self) private var session
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .title) private var codeSize: CGFloat = 84

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

  private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

  /// Brand copy beside the form at the default size; above it when text is large.
  private var layout: AnyLayout {
    isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 40))
      : AnyLayout(HStackLayout(spacing: 0))
  }

  var body: some View {
    ZStack {
      AmbientBackdrop(url: nil)

      GeometryReader { proxy in
        ScrollView(.vertical) {
          layout {
            brandPanel
              .frame(maxWidth: .infinity, alignment: .leading)

            form
              .frame(width: isAccessibilitySize ? nil : 720)
          }
          .padding(.horizontal, Theme.screenMargin + 40)
          .padding(.vertical, Theme.verticalMargin)
          .frame(maxWidth: .infinity, minHeight: proxy.size.height)
        }
        .scrollClipDisabled()
      }
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
          .font(.title3.weight(.regular))
          .foregroundStyle(Theme.textPrimary)
          .lineSpacing(4)
        Text("Sign in with your EON account to start watching.")
          .font(.body.weight(.regular))
          .foregroundStyle(Theme.textSecondary)
      }
    }
  }

  private var form: some View {
    VStack(alignment: .leading, spacing: 26) {
      Text("Sign In")
        .font(.headline.weight(.regular))
        .foregroundStyle(Theme.textPrimary)

      // Code sign-in needs a Smart TV client issued for this build's brand.
      if BrandConfig.current.supportsCodeSignIn {
        modePicker
      }

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
      .buttonStyle(.glass)
      .padding(.top, 8)
      #endif
    }
    .padding(48)
    .glassPanel()
    .animation(Theme.crossfade, value: session.signInError)
    .animation(Theme.crossfade, value: mode)
    .animation(Theme.crossfade, value: session.codeSignIn)
  }

  /// Two chips rather than a segmented picker: choosing "Code" registers the device and requests
  /// a code from the platform, so it must happen on a click, never as focus passes by.
  private var modePicker: some View {
    HStack(spacing: 14) {
      Button { mode = .password } label: {
        FilterChipLabel(title: "Password", symbol: "key.fill", isSelected: mode == .password)
      }
      .buttonStyle(.glass)
      .focused($focus, equals: .modePassword)
      Button { mode = .code } label: {
        FilterChipLabel(title: "Code", symbol: "qrcode", isSelected: mode == .code)
      }
      .buttonStyle(.glass)
      .focused($focus, equals: .modeCode)
    }
  }

  // MARK: Password

  private var passwordForm: some View {
    Group {
      field(title: "Username") {
        TextField("Email or phone", text: $username)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.emailAddress)
          .focused($focus, equals: .username)
          .onSubmit { focus = .password }
      }

      field(title: "Password") {
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
            ProgressView()
          }
          Text(session.isSigningIn ? "Signing In…" : "Sign In")
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glassProminent)
      .disabled(session.isSigningIn)
      .focused($focus, equals: .submit)
    }
  }

  // MARK: Code

  private var codeForm: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text(codeInstructions)
        .font(.caption.weight(.regular))
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      switch session.codeSignIn {
      case .idle, .requesting:
        codePlate(nil)
        HStack(spacing: 14) {
          ProgressView().tint(Theme.textSecondary)
          Text("Getting a code…")
            .font(.caption.weight(.regular))
            .foregroundStyle(Theme.textSecondary)
        }

      case .waiting(let code, let expiresAt):
        codePlate(code.otp)
        if let link = code.verificationURLComplete {
          HStack(spacing: 24) {
            QRCodeView(url: link)
              .frame(width: 176, height: 176)
            Text("Or scan this with your phone's camera to open the page with the code already filled in.")
              .font(.caption2.weight(.regular))
              .foregroundStyle(Theme.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .accessibilityElement(children: .combine)
        }
        HStack(spacing: 14) {
          ProgressView().tint(Theme.textSecondary)
          Text("Waiting for you to confirm the code…")
            .font(.caption.weight(.regular))
            .foregroundStyle(Theme.textSecondary)
          Spacer()
          HStack(spacing: 6) {
            Text("Expires in")
            Text(expiresAt, style: .timer)
              .monospacedDigit()
          }
          .font(.caption)
          .foregroundStyle(Theme.textTertiary)
          .lineLimit(1)
        }

      case .expired:
        codePlate(nil)
        errorLabel("This code has expired. Get a new one to continue.")
        Button("Get a New Code") { session.startCodeSignIn() }
          .buttonStyle(.glassProminent)
          .focused($focus, equals: .newCode)

      case .failed(let message):
        codePlate(nil)
        errorLabel(message)
        Button("Try Again") { session.startCodeSignIn() }
          .buttonStyle(.glassProminent)
          .focused($focus, equals: .newCode)
      }
    }
  }

  /// Where to enter the code, named after the page the platform gave for it.
  private var codeInstructions: String {
    if case .waiting(let code, _) = session.codeSignIn, let url = code.verificationURL {
      let page = (url.host() ?? "") + url.path()
      return "On your phone or computer, go to \(page), sign in and enter this code to link this Apple TV."
    }
    return "On your phone or computer, sign in to your EON account and enter this code to link this Apple TV."
  }

  /// The code in large, widely tracked type; a skeleton while there is none to show.
  private func codePlate(_ code: String?) -> some View {
    HStack {
      Spacer()
      if let code {
        Text(code)
          .font(.system(size: codeSize, weight: .regular, design: .monospaced))
          .kerning(codeSize / 6)
          .foregroundStyle(Theme.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
      } else {
        SkeletonBlock()
          .frame(width: codeSize * 6, height: codeSize)
      }
      Spacer()
    }
    .padding(.vertical, 26)
    .glassPanel(cornerRadius: 12)
  }

  // MARK: Pieces

  private func errorLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
      .font(.caption)
      .foregroundStyle(Theme.warning)
      .transition(.opacity)
  }

  /// A labelled system text field; the platform draws the field itself, including its focus.
  private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(Theme.textTertiary)
        .textCase(.uppercase)
        .kerning(1)
      content()
        .font(.body.weight(.regular))
    }
  }
}
