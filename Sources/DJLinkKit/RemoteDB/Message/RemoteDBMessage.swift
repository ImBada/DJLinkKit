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
    @DJLinkActor public static func fromStream(
        _ stream: any TCPConnection, _ expect: Response, _ span: TelemetrySpan = TelemetrySpan()
    ) async throws -> Message {
        let tx = span.startChild(SpanContext(op: "readFromStream", description: getMessageName(expect)))
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
        let actual = (messageType as! RemoteDBUInt16).value
        guard actual == expect.rawValue else {
            tx.setStatus(.failedPrecondition)
            tx.finish()
            throw DJLinkError(
                "Expected message type 0x\(String(expect.rawValue, radix: 16)), got 0x\(String(actual, radix: 16))")
        }
        tx.finish()
        return Message(transactionId: (txId as! RemoteDBUInt32).value, type: MessageType(rawValue: actual), args: args)
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
