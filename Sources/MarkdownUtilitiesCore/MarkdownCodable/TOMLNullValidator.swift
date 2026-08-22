import Foundation

enum TOMLNullValidator {
  static func validate<Value: Encodable>(
    _ value: Value,
    userInfo: [CodingUserInfoKey: any Sendable]
  ) throws {
    let state = State()
    let encoder = ValidatorEncoder(
      codingPath: [],
      userInfo: userInfo.reduce(into: [:]) { result, entry in result[entry.key] = entry.value },
      state: state
    )
    try value.encode(to: encoder)
    guard state.rootContainer == .keyed else {
      throw MarkdownCodecError.encodedRootIsNotMapping(format: .toml)
    }
  }
}

private extension TOMLNullValidator {
  enum ContainerKind {
    case keyed
    case unkeyed
    case single
  }

  final class State {
    var rootContainer: ContainerKind?
  }

  final class ValidatorEncoder: Encoder {
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]
    let state: State

    init(codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any], state: State) {
      self.codingPath = codingPath
      self.userInfo = userInfo
      self.state = state
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
      recordRoot(.keyed)
      return KeyedEncodingContainer(KeyedContainer<Key>(encoder: self))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
      recordRoot(.unkeyed)
      return UnkeyedContainer(encoder: self)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
      recordRoot(.single)
      return SingleValueContainer(encoder: self)
    }

    func nested(at key: any CodingKey) -> ValidatorEncoder {
      ValidatorEncoder(codingPath: codingPath + [key], userInfo: userInfo, state: state)
    }

    private func recordRoot(_ kind: ContainerKind) {
      if codingPath.isEmpty, state.rootContainer == nil {
        state.rootContainer = kind
      }
    }
  }

  struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let encoder: ValidatorEncoder
    var codingPath: [any CodingKey] { encoder.codingPath }

    mutating func encodeNil(forKey key: Key) throws {
      throw nullError(codingPath + [key])
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws { try validate(value, forKey: key) }
    mutating func encode(_ value: String, forKey key: Key) throws { try validate(value, forKey: key) }
    mutating func encode(_ value: Double, forKey key: Key) throws { try validate(value, forKey: key) }
    mutating func encode(_ value: Float, forKey key: Key) throws { try validate(value, forKey: key) }
    mutating func encode(_ value: Int, forKey key: Key) throws { try validate(value, forKey: key) }
    mutating func encode(_ value: Int8, forKey key: Key) throws { try validate(value, forKey: key) }
    mutating func encode(_ value: Int16, forKey key: Key) throws { try validate(value, forKey: key) }
    mutating func encode(_ value: Int32, forKey key: Key) throws { try validate(value, forKey: key) }
    mutating func encode(_ value: Int64, forKey key: Key) throws { try validate(value, forKey: key) }
    mutating func encode(_ value: UInt, forKey key: Key) throws {
      try validateUnsigned(value, codingPath: codingPath + [key])
    }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { try validate(value, forKey: key) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { try validate(value, forKey: key) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { try validate(value, forKey: key) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws {
      try validateUnsigned(value, codingPath: codingPath + [key])
    }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { try validate(value, forKey: key) }

    mutating func nestedContainer<NestedKey: CodingKey>(
      keyedBy keyType: NestedKey.Type,
      forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
      encoder.nested(at: key).container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
      encoder.nested(at: key).unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder {
      encoder.nested(at: ValidatorCodingKey("super"))
    }

    mutating func superEncoder(forKey key: Key) -> any Encoder {
      encoder.nested(at: key)
    }

    private func validate<T: Encodable>(_ value: T, forKey key: Key) throws {
      try value.encode(to: encoder.nested(at: key))
    }
  }

  struct UnkeyedContainer: UnkeyedEncodingContainer {
    let encoder: ValidatorEncoder
    var codingPath: [any CodingKey] { encoder.codingPath }
    var count = 0

    mutating func encodeNil() throws {
      throw nullError(codingPath + [ValidatorCodingKey(count)])
    }

    mutating func encode<T: Encodable>(_ value: T) throws {
      try value.encode(to: encoder.nested(at: ValidatorCodingKey(count)))
      count += 1
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
      keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
      defer { count += 1 }
      return encoder.nested(at: ValidatorCodingKey(count)).container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
      defer { count += 1 }
      return encoder.nested(at: ValidatorCodingKey(count)).unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder {
      defer { count += 1 }
      return encoder.nested(at: ValidatorCodingKey(count))
    }
  }

  struct SingleValueContainer: SingleValueEncodingContainer {
    let encoder: ValidatorEncoder
    var codingPath: [any CodingKey] { encoder.codingPath }

    func encodeNil() throws { throw nullError(codingPath) }
    func encode(_ value: Bool) throws {}
    func encode(_ value: String) throws {}
    func encode(_ value: Double) throws {}
    func encode(_ value: Float) throws {}
    func encode(_ value: Int) throws {}
    func encode(_ value: Int8) throws {}
    func encode(_ value: Int16) throws {}
    func encode(_ value: Int32) throws {}
    func encode(_ value: Int64) throws {}
    func encode(_ value: UInt) throws { try validateUnsigned(value, codingPath: codingPath) }
    func encode(_ value: UInt8) throws {}
    func encode(_ value: UInt16) throws {}
    func encode(_ value: UInt32) throws {}
    func encode(_ value: UInt64) throws { try validateUnsigned(value, codingPath: codingPath) }
    func encode<T: Encodable>(_ value: T) throws { try value.encode(to: encoder) }
  }

  struct ValidatorCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ string: String) {
      stringValue = string
      intValue = nil
    }

    init(_ index: Int) {
      stringValue = "Index \(index)"
      intValue = index
    }

    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { self.init(intValue) }
  }

  static func nullError(_ codingPath: [any CodingKey]) -> MarkdownCodecError {
    .tomlNullNotRepresentable(codingPath: displayPath(codingPath))
  }

  static func validateUnsigned<T: UnsignedInteger>(
    _ value: T,
    codingPath: [any CodingKey]
  ) throws {
    guard value <= T(Int64.max) else {
      throw MarkdownCodecError.tomlIntegerOutOfRange(codingPath: displayPath(codingPath))
    }
  }

  static func displayPath(_ codingPath: [any CodingKey]) -> [String] {
    codingPath.map { key in
      key.intValue.map { "[\($0)]" } ?? key.stringValue
    }
  }
}
