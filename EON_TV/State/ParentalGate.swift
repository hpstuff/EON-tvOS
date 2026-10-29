import Foundation
import EONKit
import Observation

/// Keeps adult channels behind the household PIN, as the web app does. One correct PIN
/// unlocks them until the app leaves the foreground, the profile changes or the viewer signs out.
@Observable
final class ParentalGate {
  enum Outcome: Equatable {
    case unlocked
    case wrongPin
    case failed(String)
  }

  /// The PIN the platform asks for has four digits.
  static let pinLength = 4

  private(set) var isUnlocked = false
  private var repository: ParentalControlRepository?

  func attach(_ repository: ParentalControlRepository) {
    self.repository = repository
    isUnlocked = false
  }

  func lock() {
    isUnlocked = false
  }

  func needsPin(for channel: Channel) -> Bool {
    channel.requiresParentalPin && !isUnlocked
  }

  /// Checks `pin` against the household PIN without unlocking anything.
  func verify(_ pin: String) async -> Outcome {
    guard let repository else { return .failed("Parental controls aren't available right now.") }
    do {
      return try await repository.verify(pin: pin) ? .unlocked : .wrongPin
    } catch {
      return .failed(ErrorPresenter.message(for: error, context: .content))
    }
  }

  /// Checks `pin` and unlocks adult channels when it is right.
  func unlock(with pin: String) async -> Outcome {
    let outcome = await verify(pin)
    if outcome == .unlocked { isUnlocked = true }
    return outcome
  }
}
