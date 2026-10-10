import DJLinkKit
import DJLinkTestSupport
import Testing

struct RemoteDBFieldsTests {
    @Suite("UInt8") struct UInt8Tests {
        func check(_ num: RemoteDBUInt8) {
            #expect(num.value == 5)
            #expect(num.data.count == 1)
            #expect(num.data[0] == 0x05)
            #expect(num.buffer.count == 2)
            #expect(num.buffer[0] == FieldType.uint8.rawValue)
        }
        @Test("encodes") func encodes() { check(RemoteDBUInt8(5)) }
        @Test("decodes") func decodes() throws { check(try RemoteDBUInt8([0x05])) }
    }
    @Suite("UInt16") struct UInt16Tests {
        func check(_ num: RemoteDBUInt16) {
            #expect(num.value == 5)
            #expect(num.data.count == 2)
            #expect(num.data == [0x00, 0x05])
            #expect(num.buffer.count == 3)
            #expect(num.buffer[0] == FieldType.uint16.rawValue)
        }
        @Test("encodes") func encodes() { check(RemoteDBUInt16(5)) }
        @Test("decodes") func decodes() throws { check(try RemoteDBUInt16([0x00, 0x05])) }
    }
    @Suite("UInt32") struct UInt32Tests {
        func check(_ num: RemoteDBUInt32) {
            #expect(num.value == 5)
            #expect(num.data.count == 4)
            #expect(num.data == [0x00, 0x00, 0x00, 0x05])
            #expect(num.buffer.count == 5)
            #expect(num.buffer[0] == FieldType.uint32.rawValue)
        }
        @Test("encodes") func encodes() { check(RemoteDBUInt32(5)) }
        @Test("decodes") func decodes() throws { check(try RemoteDBUInt32([0x00, 0x00, 0x00, 0x05])) }
    }
    @Suite("String") struct StringTests {
        func check(_ string: RemoteDBString) {
            #expect(string.value == "test")
            #expect(string.data.count == 10)
            #expect(string.data == [0x00, 0x74, 0x00, 0x65, 0x00, 0x73, 0x00, 0x74, 0x00, 0x00])
            #expect(string.buffer.count == 15)
            #expect(string.buffer[0] == FieldType.string.rawValue)
        }
        @Test("encodes") func encodes() { check(RemoteDBString("test")) }
        @Test("decodes") func decodes() throws {
            check(try RemoteDBString([0x00, 0x74, 0x00, 0x65, 0x00, 0x73, 0x00, 0x74, 0x00, 0x00]))
        }
    }
    @Suite("Binary") struct BinaryTests {
        @Test("encodes and decodes") func encodesAndDecodes() {
            let string = RemoteDBBinary([0x0a, 0x0b, 0x0c])
            #expect(string.value == [0x0a, 0x0b, 0x0c])
            #expect(string.data.count == 3)
            #expect(string.data == [0x0a, 0x0b, 0x0c])
            #expect(string.buffer.count == 8)
            #expect(string.buffer[0] == FieldType.binary.rawValue)
        }
    }
    @Suite("readField") @DJLinkActor struct ReadFieldTests {
        @Test("raises an error when the wrong field is read") func wrongField() async {
            let socket = FakeTCPConnection()
            socket.inject([FieldType.uint16.rawValue])
            await #expect(throws: DJLinkError("Expected UInt8 but got UInt16")) { try await readField(socket, .uint8) }
        }
        @Test("reads a fixed size integer") func integer() async throws {
            let socket = FakeTCPConnection()
            socket.inject([FieldType.uint8.rawValue, 0x05])
            let data = try await readField(socket, .uint8)
            #expect(data is RemoteDBUInt8)
            #expect((data as? RemoteDBUInt8)?.value == 0x05)
        }
        @Test("reads a variable sized binary field") func binary() async throws {
            let socket = FakeTCPConnection()
            socket.inject([FieldType.binary.rawValue, 0x00, 0x00, 0x00, 0x02, 0x01, 0x02])
            let data = try await readField(socket, .binary)
            #expect(data is RemoteDBBinary)
            // 원본과 다름: Buffer 형 검사는 Swift의 바이트 배열 형으로 보장된다.
            #expect((data as? RemoteDBBinary)?.value == [0x01, 0x02])
        }
        @Test("does not read 0 length data of a empty binary field") func emptyBinary() async throws {
            let socket = FakeTCPConnection()
            socket.inject([FieldType.binary.rawValue, 0x00, 0x00, 0x00, 0x00])
            let data = try await readField(socket, .binary)
            #expect(data is RemoteDBBinary)
            // 원본과 다름: Buffer 형 검사는 Swift의 바이트 배열 형으로 보장된다.
            #expect((data as? RemoteDBBinary)?.value == [])
            #expect(!socket.readCalls.contains { $0 == 0 })
        }
    }
}
