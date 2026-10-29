import SwiftUI

/// Four-digit PIN entry on a focusable keypad, for adult channels and PIN-protected profiles.
/// The PIN is checked as soon as the last digit is entered; a wrong one shakes the dots and
/// clears them for another try.
struct PinEntryView: View {
  let title: String
  var message: String?
  var length = ParentalGate.pinLength
  let submit: (String) async -> ParentalGate.Outcome
  let onSuccess: () -> Void
  let onCancel: () -> Void

  @State private var digits = ""
  @State private var error: String?
  @State private var isChecking = false
  @State private var attempts = 0
  @FocusState private var focus: Key?

  enum Key: Hashable {
    case digit(Int), delete, cancel
  }

  private static let rows: [[Int?]] = [[1, 2, 3], [4, 5, 6], [7, 8, 9], [nil, 0, -1]]

  var body: some View {
    VStack(spacing: 32) {
      Image(systemName: "lock.fill")
        .font(.title3)
        .foregroundStyle(Theme.textSecondary)
      Text(title)
        .font(.title3.weight(.regular))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
      if let message {
        Text(message)
          .font(.body.weight(.regular))
          .foregroundStyle(Theme.textSecondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 900)
      }

      HStack(spacing: 28) {
        ForEach(0..<length, id: \.self) { index in
          Circle()
            .fill(index < digits.count ? Color.white : Color.clear)
            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 3))
            .frame(width: 30, height: 30)
        }
      }
      .modifier(ShakeEffect(travel: CGFloat(attempts)))
      .animation(.easeOut(duration: 0.12), value: digits)
      .accessibilityElement()
      .accessibilityLabel("\(digits.count) of \(length) digits entered")

      Text(error ?? " ")
        .font(.caption.weight(.regular))
        .foregroundStyle(Theme.textSecondary)
        .opacity(error == nil ? 0 : 1)

      // Not disabled while checking: that would push focus onto Cancel, where the next press
      // would back out. `enter` ignores digits until the check is done instead.
      keypad

      Button("Cancel", action: onCancel)
        .buttonStyle(.glass)
        .focused($focus, equals: .cancel)
    }
    .focusSection()
    .defaultFocus($focus, .digit(1), priority: .userInitiated)
    .onExitCommand(perform: onCancel)
  }

  private var keypad: some View {
    VStack(spacing: 20) {
      ForEach(Self.rows.indices, id: \.self) { row in
        HStack(spacing: 20) {
          ForEach(Self.rows[row].indices, id: \.self) { column in
            key(Self.rows[row][column])
          }
        }
      }
    }
  }

  @ViewBuilder
  private func key(_ value: Int?) -> some View {
    switch value {
    case .none:
      // An invisible key keeps the bottom row on the same grid as the rows above.
      Button {} label: { Text("0").frame(width: 84, height: 52) }
        .buttonStyle(.glass)
        .hidden()
    case .some(-1):
      Button { delete() } label: {
        Image(systemName: "delete.left")
          .frame(width: 84, height: 52)
      }
      .buttonStyle(.glass)
      .focused($focus, equals: .delete)
      .accessibilityLabel("Delete")
    case .some(let digit):
      Button { enter(digit) } label: {
        Text("\(digit)")
          .font(.title3.weight(.medium).monospacedDigit())
          .frame(width: 84, height: 52)
      }
      .buttonStyle(.glass)
      .focused($focus, equals: .digit(digit))
    }
  }

  private func enter(_ digit: Int) {
    guard digits.count < length, !isChecking else { return }
    digits.append(String(digit))
    error = nil
    if digits.count == length { check() }
  }

  private func delete() {
    guard !digits.isEmpty, !isChecking else { return }
    digits.removeLast()
  }

  private func check() {
    isChecking = true
    let pin = digits
    Task {
      let outcome = await submit(pin)
      isChecking = false
      switch outcome {
      case .unlocked:
        onSuccess()
      case .wrongPin:
        error = "That PIN isn't right. Try again."
        withAnimation(.linear(duration: 0.4)) { attempts += 1 }
        digits = ""
      case .failed(let message):
        error = message
        digits = ""
      }
    }
  }
}

/// A horizontal shake, one full shake per whole step of `travel`.
private struct ShakeEffect: GeometryEffect {
  var travel: CGFloat

  var animatableData: CGFloat {
    get { travel }
    set { travel = newValue }
  }

  func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(CGAffineTransform(translationX: 16 * sin(travel * .pi * 6), y: 0))
  }
}
