public final class Message: Sendable {
    // 원본은 writeMessage가 transactionId를 바꾼다. 액터 격리로 같은 순서를 보장한다.
    @DJLinkActor public var transactionId: Int?
    public let type: MessageType
    public let args: [Field]
    @DJLinkActor public init(transactionId: Int? = nil, type: MessageType, args: [Field]) {
        self.transactionId = transactionId
        self.type = type
        self.args = args
    }
    @DJLinkActor public var buffer: [UInt8] {
        var argList = [UInt8].alloc(12)
        for (index, arg) in args.enumerated() { argList[index] = Self.argumentType(arg.type) }
        var fields: [Field] = [
            RemoteDBUInt32(REMOTEDB_MAGIC), RemoteDBUInt32(transactionId ?? 0),
            RemoteDBUInt16(type.rawValue), RemoteDBUInt8(args.count), RemoteDBBinary(argList),
        ]
        for (index, arg) in args.enumerated() {
            if arg.type == .binary, index != 0, args[index - 1].type == .uint32,
                (args[index - 1] as? any NumberField)?.value == 0
            {
                continue
            }
            fields.append(arg)
        }
        return fields.flatMap(\.buffer)
    }
    public var data: RemoteDBResponseData { get throws { try responseTransform(type, args) } }
    /// 응답 하나를 기다리며 건너뛸 수 있는 다른 번호의 메시지 수. 넘으면 오류로 끝낸다.
    /// 끼어드는 메시지가 끝없이 오면 소켓의 유휴 제한(#47)이 늘어나기만 해서 질의가 끝나지 않기 때문이다.
    public static let maxSkippedMessages = 16
    /// - Parameter expectedTransactionId: 원본은 응답을 순서대로 읽고 트랜잭션 번호를 보지 않는다(기본값 nil, 원본 동작).
    ///   값을 주면 그 번호가 아닌 메시지(CDJ가 요청하지 않고 먼저 보낸 것, 이전 질의에서 남은 것)는 끝까지 읽어 버리고
    ///   디버그 로그만 남긴 채 다음 메시지를 읽는다. 종류 검사는 번호가 맞는 메시지에만 한다(PLAN §9, #46).
    @DJLinkActor public static func fromStream(
        _ stream: any TCPConnection, _ expect: Response, _ span: TelemetrySpan = TelemetrySpan(),
        expectedTransactionId: Int? = nil, logger: any Logger = noopLogger
    ) async throws -> Message {
        let tx = span.startChild(SpanContext(op: "readFromStream", description: getMessageName(expect)))
        var skipped = 0
        while true {
            let (txId, actual, args) = try await readFrame(stream)
            if let expectedTransactionId, txId != expectedTransactionId {
                skipped += 1
                guard skipped <= maxSkippedMessages else {
                    tx.setStatus(.failedPrecondition)
                    tx.finish()
                    throw DJLinkError(
                        "Skipped more than \(maxSkippedMessages) messages while waiting for transaction 0x\(String(expectedTransactionId, radix: 16))"
                    )
                }
                logger.debug(
                    "[remotedb] Skipped message type 0x\(String(actual, radix: 16)) with transaction 0x\(String(txId, radix: 16)) while waiting for transaction 0x\(String(expectedTransactionId, radix: 16))"
                )
                continue
            }
            guard actual == expect.rawValue else {
                tx.setStatus(.failedPrecondition)
                tx.finish()
                throw DJLinkError(
                    "Expected message type 0x\(String(expect.rawValue, radix: 16)), got 0x\(String(actual, radix: 16))")
            }
            tx.finish()
            return Message(transactionId: txId, type: MessageType(rawValue: actual), args: args)
        }
    }
    /// 메시지 하나를 끝까지 읽는다(매직, 트랜잭션, 종류, 인자 수, 인자 형 목록, 인자). 종류는 검사하지 않는다.
    @DJLinkActor private static func readFrame(_ stream: any TCPConnection) async throws -> (
        transactionId: Int, type: Int, args: [Field]
    ) {
        let magic = try await readField(stream, .uint32)
        guard (magic as? any NumberField)?.value == REMOTEDB_MAGIC else {
            throw DJLinkError("Did not receive expected magic value. Corrupt message")
        }
        let txId = try await readField(stream, .uint32)
        let messageType = try await readField(stream, .uint16)
        let argCount = try await readField(stream, .uint8)
        let argList = try await readField(stream, .binary)
        let types = (argList as! RemoteDBBinary).value
        var args: [Field] = []
        for i in 0..<(argCount as! RemoteDBUInt8).value {
            guard types.indices.contains(i) else {
                // 원본은 undefined 인자 형을 readField에 넘겨 TypeError로 거절한다.
                throw DJLinkError("Cannot read properties of undefined (reading 'name')")
            }
            if types[i] == 3, i > 0, (args[i - 1] as? any NumberField)?.value == 0 {
                args.append(RemoteDBBinary([]))
                continue
            }
            let type: FieldType
            switch types[i] {
            case 2: type = .string
            case 3: type = .binary
            case 6: type = .uint32
            default: throw DJLinkError("Unknown argument type")
            }
            args.append(try await readField(stream, type))
        }
        return ((txId as! RemoteDBUInt32).value, (messageType as! RemoteDBUInt16).value, args)
    }
    private static func argumentType(_ type: FieldType) -> UInt8 {
        switch type {
        case .string: 2
        case .binary: 3
        case .uint32: 6
        case .uint8, .uint16: 0
        }
    }
}
