/// 원본 `EventEmitter`의 이벤트 이름. `Owner`는 이벤트를 내는 형, `Payload`는 넘기는 값이다.
///
/// 각 형은 제약 걸린 확장으로 이름을 선언한다.
/// ```swift
/// extension EventName where Owner == DeviceManager, Payload == Device {
///     public static var connected: Self { .init("connected") }
/// }
/// deviceManager.on(.connected) { device in … }
/// ```
public struct EventName<Owner, Payload>: Hashable, Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }
}

/// `on`·`once`가 돌려주는 구독. `off`에 넘긴다(원본은 함수 자체로 끊는다).
public struct EventSubscription: Hashable, Sendable {
    public let id: UInt64
    public let name: String
}

/// 원본 `EventEmitter`(Node `events`)를 옮긴 것. 구독자 여럿에게 차례로 나눠 준다.
///
/// - `emit`은 구독자를 등록한 순서대로 동기로 부른다(Node와 같다).
/// - `emit` 도중 더하거나 뺀 구독자는 그 `emit`에 반영되지 않는다(Node처럼 목록을 복사해 돈다).
/// - `stream(_:)`으로 AsyncStream 구독도 받을 수 있다.
@DJLinkActor
public final class EventHub<Owner> {
    private struct Listener {
        let id: UInt64
        let once: Bool
        let call: @DJLinkActor (Any) -> Void
    }

    private var nextID: UInt64 = 0
    private var listeners: [String: [Listener]] = [:]

    public nonisolated init() {}

    @discardableResult
    public func on<Payload>(
        _ event: EventName<Owner, Payload>,
        _ handler: @escaping @DJLinkActor (Payload) -> Void
    ) -> EventSubscription {
        add(event, once: false, handler)
    }

    @discardableResult
    public func once<Payload>(
        _ event: EventName<Owner, Payload>,
        _ handler: @escaping @DJLinkActor (Payload) -> Void
    ) -> EventSubscription {
        add(event, once: true, handler)
    }

    public func off(_ subscription: EventSubscription) {
        guard var list = listeners[subscription.name] else { return }
        list.removeAll { $0.id == subscription.id }
        listeners[subscription.name] = list.isEmpty ? nil : list
    }

    /// 구독자가 하나라도 있었으면 true(Node `emit`의 반환값).
    @discardableResult
    public func emit<Payload>(_ event: EventName<Owner, Payload>, _ payload: Payload) -> Bool {
        guard let snapshot = listeners[event.name], !snapshot.isEmpty else { return false }
        if snapshot.contains(where: \.once) {
            let onceIDs = Set(snapshot.filter(\.once).map(\.id))
            listeners[event.name]?.removeAll { onceIDs.contains($0.id) }
            if listeners[event.name]?.isEmpty == true { listeners[event.name] = nil }
        }
        for listener in snapshot {
            listener.call(payload)
        }
        return true
    }

    public func listenerCount<Payload>(_ event: EventName<Owner, Payload>) -> Int {
        listeners[event.name]?.count ?? 0
    }

    public func removeAllListeners() {
        listeners.removeAll()
    }

    /// `removeAllListeners(event)`: 이 이벤트의 구독만 지운다.
    public func removeAllListeners<Payload>(_ event: EventName<Owner, Payload>) {
        listeners[event.name] = nil
    }

    /// 이 이벤트를 AsyncStream으로 받는다. 스트림이 끝나면 구독을 푼다.
    public func stream<Payload: Sendable>(
        _ event: EventName<Owner, Payload>,
        bufferingPolicy: AsyncStream<Payload>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<Payload> {
        let (stream, continuation) = AsyncStream.makeStream(of: Payload.self, bufferingPolicy: bufferingPolicy)
        let subscription = on(event) { continuation.yield($0) }
        continuation.onTermination = { [weak self] _ in
            Task { @DJLinkActor in self?.off(subscription) }
        }
        return stream
    }

    private func add<Payload>(
        _ event: EventName<Owner, Payload>,
        once: Bool,
        _ handler: @escaping @DJLinkActor (Payload) -> Void
    ) -> EventSubscription {
        nextID += 1
        let listener = Listener(id: nextID, once: once) { value in
            handler(value as! Payload)
        }
        listeners[event.name, default: []].append(listener)
        return EventSubscription(id: listener.id, name: event.name)
    }
}

/// 원본의 `on: Emitter['on'] = this.#emitter.addListener.bind(...)` 같은 공개 구독 창구.
/// 따르는 형은 `let emitter = EventHub<Self>()`만 두면 된다.
@DJLinkActor
public protocol EventEmitting: AnyObject {
    var emitter: EventHub<Self> { get }
}

extension EventEmitting {
    @discardableResult
    public func on<Payload>(
        _ event: EventName<Self, Payload>,
        _ handler: @escaping @DJLinkActor (Payload) -> Void
    ) -> EventSubscription {
        emitter.on(event, handler)
    }

    @discardableResult
    public func once<Payload>(
        _ event: EventName<Self, Payload>,
        _ handler: @escaping @DJLinkActor (Payload) -> Void
    ) -> EventSubscription {
        emitter.once(event, handler)
    }

    public func off(_ subscription: EventSubscription) {
        emitter.off(subscription)
    }

    public func events<Payload: Sendable>(_ event: EventName<Self, Payload>) -> AsyncStream<Payload> {
        emitter.stream(event)
    }
}
