import Dispatch

/// 원본(Node)은 이벤트 루프 하나에서 모든 콜백을 차례로 부른다.
/// 그 순서를 그대로 지키려고 상태를 가진 형은 모두 이 global actor에 묶는다.
/// 소켓 수신·타이머도 같은 직렬 큐에서 돌아서, 패킷이 온 순서대로 처리된다.
@globalActor
public actor DJLinkActor {
    public static let shared = DJLinkActor()

    /// actor의 실행기. 소켓 DispatchSource와 타이머도 이 큐에 건다.
    package static let queue = DispatchSerialQueue(label: "DJLinkKit.DJLinkActor")

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        Self.queue.asUnownedSerialExecutor()
    }

    /// `DJLinkActor.queue` 위에서 도는 콜백(DispatchSource 등)에서 격리를 가정하고 바로 부른다.
    /// 큐 밖에서 부르면 멈춘다.
    package static func assumeIsolated<T>(
        _ operation: @DJLinkActor () throws -> T,
        file: StaticString = #fileID,
        line: UInt = #line
    ) rethrows -> T {
        typealias Plain = () throws -> T
        shared.preconditionIsolated(file: file, line: line)
        return try withoutActuallyEscaping(operation) { isolated in
            try unsafeBitCast(isolated, to: Plain.self)()
        }
    }
}
