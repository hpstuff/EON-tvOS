import Foundation
import CryptoKit
import CommonCrypto

extension String {

  func fromBase64() -> String? {
    guard let data = Data(base64Encoded: self) else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  func toBase64() -> String {
    return Data(self.utf8).base64EncodedString()
  }

  func sha256() -> String? {
    guard let data = self.data(using: .utf8) else {
      return nil
    }
    let digest = SHA256.hash(data: data)
    let hashString = digest
      .compactMap { String(format: "%02x", $0) }
      .joined()
    return hashString
  }
}

//extension String: @retroactive Identifiable {
//    public var id: String { self }
//}

extension Data {
    var bytes: [UInt8] {
        return [UInt8](self)
    }
}

struct HexEncodingOptions: OptionSet {
    let rawValue: Int
    static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
}

extension Sequence where Element == UInt8 {
    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return self.map { String(format: format, $0) }.joined()
    }
}

func urlsafeEncode(_ string: String) -> String {
    var t = string
    t = t.replacingOccurrences(of: "+", with: "-")
         .replacingOccurrences(of: "/", with: "_")
         .replacingOccurrences(of: "=", with: "")
    return t
}

func urlsafeDecode(_ string: String) -> String {
    var t = string
    t = t.replacingOccurrences(of: "-", with: "+")
         .replacingOccurrences(of: "_", with: "/")
    return t
}

func decodeEonStreamKey(from streamKey: String) -> (key: Data, iv: Data)? {
  var base64 = urlsafeDecode(streamKey)
  
  while base64.count % 4 != 0 {
    base64.append("=")
  }

  guard let keyData = Data(base64Encoded: base64) else {
    return nil
  }

  let blockSize = 16
  var iv = Data(count: blockSize)
  let result = iv.withUnsafeMutableBytes { ivBytes -> Int32 in
    guard let baseAddress = ivBytes.baseAddress else { return errSecParam }
    return SecRandomCopyBytes(kSecRandomDefault, blockSize, baseAddress)
  }

  guard result == errSecSuccess else {
    print("Failed to generate random IV")
    return nil
  }

  return (keyData, iv)
}

func aesEncryptCBC(iv: Data, key: Data, plaintext: Data) -> Data? {
  let keyLength = key.count
  guard [16, 24, 32].contains(keyLength) else {
    print("Invalid AES key size: \(keyLength)")
    return nil
  }

  // Prepare output buffer
  let bufferSize = plaintext.count + kCCBlockSizeAES128
  var buffer = [UInt8](repeating: 0, count: bufferSize)
  var numBytesEncrypted: size_t = 0

  let status = key.withUnsafeBytes { keyBytes in
    iv.withUnsafeBytes { ivBytes in
      plaintext.withUnsafeBytes { plaintextBytes in
        CCCrypt(
          CCOperation(kCCEncrypt),
          CCAlgorithm(kCCAlgorithmAES128),
          CCOptions(kCCOptionPKCS7Padding),
          keyBytes.baseAddress, keyLength,
          ivBytes.baseAddress,
          plaintextBytes.baseAddress, plaintext.count,
          &buffer, bufferSize,
          &numBytesEncrypted
        )
      }
    }
  }

  guard status == kCCSuccess else {
    print("Encryption failed with status: \(status)")
    return nil
  }

  return Data(bytes: buffer, count: numBytesEncrypted)
}

func debounce(interval: Int, queue: DispatchQueue, action: @escaping (() -> Void)) -> () -> Void {
  var lastFireTime = DispatchTime.now()
  let dispatchDelay = DispatchTimeInterval.milliseconds(interval)

  return {
    lastFireTime = DispatchTime.now()
    let dispatchTime: DispatchTime = DispatchTime.now() + dispatchDelay

    queue.asyncAfter(deadline: dispatchTime) {
      let when: DispatchTime = lastFireTime + dispatchDelay
      let now = DispatchTime.now()
      if now.rawValue >= when.rawValue {
        action()
      }
    }
  }
}

func areTimestampsClose(_ t1: TimeInterval, _ t2: TimeInterval, marginSeconds: TimeInterval) -> Bool {
    return abs(t1 - t2) <= marginSeconds
}

func isScheduleLive(_ schedule: Schedule, liveTime: Int) -> Bool {
  return schedule.startTime < liveTime && schedule.endTime > liveTime
}


extension Date {
  public var startOfTheDay: Date {
    get {
      let calendar = Calendar.current
      return calendar.startOfDay(for: self)
    }
  }
  
  public var timestampSince1970: Int {
    get { Int(timeIntervalSince1970) }
  }
  
  public var timestamp: Int {
    get { timestampSince1970 * 1000 }
  }
  
  public var endOfTheDay: Date {
    get {
      let calendar = Calendar.current
      return calendar.date(byAdding: .day, value: 1, to: self.startOfTheDay)!.addingTimeInterval(-1)
    }
  }
  
  public func toHourString() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: self)
  }
  
  public func toWeekDayString() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "E dd.MM"
    return formatter.string(from: self)
  }
}

func hourSize(startTime: Int, endTime: Int) -> CGFloat {
  return (CGFloat(endTime) - CGFloat(startTime)) / (60*60*1000)
}
