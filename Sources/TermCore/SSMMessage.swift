import Foundation
import CryptoKit

// Wire layout follows aws/session-manager-plugin src/message (Apache-2.0).
public struct SSMMessage: Sendable {
    public var type: String
    public var sequence: UInt64
    public var payloadType: UInt32
    public var payload: Data
    public var id: UUID
    public init(type: String, sequence: UInt64 = 0, payloadType: UInt32 = 0, payload: Data, id: UUID = UUID()) {
        self.type = type; self.sequence = sequence; self.payloadType = payloadType; self.payload = payload; self.id = id
    }
    public func encode() -> Data {
        var data = Data()
        data.put(UInt32(116)); data.append(Data(type.utf8)); data.append(Data(repeating: 32, count: max(0, 32 - type.utf8.count)))
        data.put(UInt32(1)); data.put(UInt64(Date().timeIntervalSince1970 * 1000)); data.put(sequence)
        data.put(UInt64(sequence == 0 && type == "input_stream_data" ? 1 : 0))
        var uuid = id.uuid
        let bytes = withUnsafeBytes(of: &uuid) { Data($0) }
        // The protocol puts the UUID's low 64 bits before its high 64 bits.
        data.append(bytes.suffix(8)); data.append(bytes.prefix(8))
        data.append(Data(SHA256.hash(data: payload))); data.put(payloadType); data.put(UInt32(payload.count)); data.append(payload)
        return data
    }
    public init(decode data: Data) throws {
        guard data.count >= 120, data.number(at: 0, as: UInt32.self) == 116,
              data.number(at: 36, as: UInt32.self) == 1 else { throw ConnectionError.message("Invalid SSM message header.") }
        let length = Int(data.number(at: 116, as: UInt32.self))
        guard length <= 4 * 1024 * 1024, data.count == 120 + length else { throw ConnectionError.message("Invalid SSM message length.") }
        payload = data.subdata(in: 120..<data.count)
        guard Data(SHA256.hash(data: payload)) == data.subdata(in: 80..<112) else { throw ConnectionError.message("Invalid SSM message digest.") }
        type = String(decoding: data[4..<36].prefix(while: { $0 != 0 }), as: UTF8.self).trimmingCharacters(in: .whitespaces)
        sequence = data.number(at: 48, as: UInt64.self); payloadType = data.number(at: 112, as: UInt32.self)
        let b = Array(data[72..<80] + data[64..<72])
        id = UUID(uuid: (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]))
    }
}
extension Data {
    mutating func put<T: FixedWidthInteger>(_ value: T) { var big = value.bigEndian; Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) } }
    func number<T: FixedWidthInteger>(at offset: Int, as: T.Type) -> T { self[offset..<(offset + MemoryLayout<T>.size)].reduce(T(0)) { ($0 << 8) | T($1) } }
}
