import Foundation
import Combine

@available(iOS 13.0, macOS 10.15, *)
open class SerializableStore<M: SerializableModelType>: Store<M> {
  public enum DiffingOption {
    case none
    case sync
    case async
  }
  /// The diffing dispatch strategy.
  public var diffing: DiffingOption = .async
  /// Publishes a stream with the latest model changes.
  @Published public var diffs: PropertyDiffSet = PropertyDiffSet(diffs: [:], transaction: nil)
  /// Publishes a JSON data stream with the econded diffs.
  @Published public var jsonDiffs: Data = Data()

  // Private.
  private var queue = DispatchQueue(label: "io.store.serializable.diff")
  private var transactions = Set<String>()
  private let jsonEncoder = JSONEncoder()
  private var snapshot: [String: Any] = [:]

  override public init(model: M) {
    super.init(model: model)
    self.snapshot = model.encode(flatten: true)
  }

  override open func updateModel(transaction: AnyTransaction?, closure: (inout M) -> (Void)) {
    let transaction = transaction ?? SerializableUpdateModelTransaction()
    super.updateModel(transaction: transaction, closure: closure)
  }

  override open func didUpdateModel(transaction: AnyTransaction?, old: M, new: M) {
    guard let transaction = transaction, diffing != .none else {
      return
    }
    func dispatch(option: DiffingOption, execute: @escaping () -> Void) {
      if option == .sync {
        queue.sync(execute: execute)
      } else if option == .async {
        queue.async(execute: execute)
      }
    }
    dispatch(option: diffing) {
      self.transactions.insert(transaction.transactionIdentifier)
      /// The resulting dictionary won't be nested and all of the keys will be paths.
      let encodedModel = new.encode(flatten: true)
      var diffs: [String: PropertyDiff] = [:]
      for (key, value) in encodedModel {
        // The (`keyPath`, `value`) pair was not in the previous snapshot.
        if self.snapshot[key] == nil {
          diffs[key] = PropertyDiff(type: .added, value: value)
        // The (`keyPath`, `value`) pair has changed value.
        } else if let lhs = self.snapshot[key], !dynamicEqual(lhs: lhs, rhs: value) {
          diffs[key] = PropertyDiff(type: .changed, value: value)
        }
      }
      // The (`keyPath`, `value`) was removed from the snapshot.
      for (key, value) in self.snapshot where encodedModel[key] == nil {
        diffs[key] = PropertyDiff(type: .removed, value: value)
      }

      // Updates the publisher.
      self.diffs = PropertyDiffSet(diffs: diffs, transaction: transaction)
      self.jsonDiffs = (try? self.jsonEncoder.encode(diffs)) ?? Data()
      self.snapshot = encodedModel

      print("▩ [diff] (\(transaction.transactionIdentifier)) \(transaction.identifier) \(diffs.log)")
    }
  }
}

// MARK: - PropertyDiff

@available(iOS 13.0, macOS 10.15, *)
public struct PropertyDiff: CustomStringConvertible, Encodable {
  public enum ChangeType: String {
    case added
    case changed
    case removed
  }
  /// The (`keyPath`, `value`) pair has been added/removed or changed as a result of this
  /// last transaction.
  public let type: ChangeType
  /// The new value if `added` is `changed` or `type`, the old value otherwise.
  public let value: Any
  /// Human readable description.
  public var description: String {
    return "<\(type) ⇒ \(value)>"
  }

  /// Encodes this value into the given encoder.
  public func encode(to encoder: Encoder) throws {
    if type == .removed {
      var container = encoder.singleValueContainer()
      try container.encodeNil()
    } else {
      if let value = value as? Encodable {
        try value.encode(to: encoder)
      }
    }
  }
}

@available(iOS 13.0, macOS 10.15, *)
extension Dictionary where Key == String, Value == PropertyDiff {
  /// String representation of the diffed entries.
  var log: String {
    let keys = self.keys.sorted()
    var formats: [String] = []
    for key in keys {
      formats.append("\(key): \(self[key]!)")
    }
    return "{\(formats.joined(separator: ", "))}"
  }
}

@available(iOS 13.0, macOS 10.15, *)
public struct PropertyDiffSet {
  /// The set of (`keyPath`, `value`) pair that has been added/removed or changed.
  public let diffs: [String: PropertyDiff]
  /// The transaction that caused this change set.
  public weak var transaction: AnyTransaction?
}

// MARK: - SerializableUpdateModelTransaction

@available(iOS 13.0, macOS 10.15, *)
public final class SerializableUpdateModelTransaction: AnyTransaction {
  /// Every access to `SerializableStore.updateModel` without a transaction argument results in
  /// a `SERIALIZABLE_UPDATE_MODEL` transaction.
  public let identifier: String = "SERIALIZABLE_UPDATE_MODEL"
  /// Randomized identifier for the current transaction that preserve the temporal information.
  public let transactionIdentifier: String = PushID.default.make()
  /// - note: SERIALIZABLE_UPDATE_MODEL transaction don't have an associated operation..
  public let strategy: Dispatcher.Strategy = .async(nil)
  /// - note: SERIALIZABLE_UPDATE_MODEL transaction don't have an associated operation..
  public var error: Dispatcher.TransactionGroupError? = nil
  /// - note: SERIALIZABLE_UPDATE_MODEL transaction don't have an associated operation..
  public  var operation: AsyncOperation {
    fatalError("SERIALIZABLE_UPDATE_MODEL transaction don't have an associated operation.")
  }
  /// - note: SERIALIZABLE_UPDATE_MODEL transaction don't have an associated operation..
  public var opaqueStoreRef: AnyStoreType? = nil
  /// Represents the progress of the transaction.
  public var state: TransactionState = .pending
  
  /// - note: SERIALIZABLE_UPDATE_MODEL transaction don't have an associated operation..
  public func on(_ queueWithStrategy: Dispatcher.Strategy) -> Self {
    // No op.
    return self
  }

  /// - note: SERIALIZABLE_UPDATE_MODEL transaction don't have an associated operation..
  public func perform(operation: AsyncOperation) {
    // No op
  }

  /// - note: SERIALIZABLE_UPDATE_MODEL transaction don't have an associated operation..
  public func run(handler: Dispatcher.TransactionCompletionHandler) {
    // No op
  }
}