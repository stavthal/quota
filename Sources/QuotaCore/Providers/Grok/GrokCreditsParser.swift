import Foundation

public struct GrokCreditsConfig: Sendable, Equatable {
    public var creditUsagePercent: Double
    public var billingPeriodStart: Date?
    public var billingPeriodEnd: Date?
    public var onDemandCapCents: Int
    public var onDemandUsedCents: Int

    public init(
        creditUsagePercent: Double,
        billingPeriodStart: Date? = nil,
        billingPeriodEnd: Date? = nil,
        onDemandCapCents: Int = 0,
        onDemandUsedCents: Int = 0
    ) {
        self.creditUsagePercent = creditUsagePercent
        self.billingPeriodStart = billingPeriodStart
        self.billingPeriodEnd = billingPeriodEnd
        self.onDemandCapCents = onDemandCapCents
        self.onDemandUsedCents = onDemandUsedCents
    }
}

/// Minimal protobuf + gRPC-web decoder for `GetGrokCreditsConfig`.
public enum GrokCreditsParser {
    public static func config(fromGrpcWebBody body: Data) throws -> GrokCreditsConfig {
        let message = try unwrapGrpcWebMessage(body)
        guard let configMsg = firstLengthDelimited(message, field: 1) else {
            throw GrokProviderError.emptyUsage
        }

        var percent: Double = 0
        var start: Date?
        var end: Date?
        var capCents = 0
        var usedCents = 0

        for field in try fields(of: configMsg) {
            switch (field.number, field.wire) {
            case (1, .fixed32):
                percent = Double(Float(bitPattern: field.fixed32BitPattern))
            case (2, .lengthDelimited):
                capCents = parseCent(field.bytes)
            case (3, .lengthDelimited):
                usedCents = parseCent(field.bytes)
            case (4, .lengthDelimited):
                start = parseTimestamp(field.bytes)
            case (5, .lengthDelimited):
                end = parseTimestamp(field.bytes)
            default:
                continue
            }
        }

        return GrokCreditsConfig(
            creditUsagePercent: percent,
            billingPeriodStart: start,
            billingPeriodEnd: end,
            onDemandCapCents: capCents,
            onDemandUsedCents: usedCents
        )
    }

    public static func snapshot(
        from config: GrokCreditsConfig,
        fetchedAt: Date = Date()
    ) -> UsageSnapshot {
        let resetsAt = config.billingPeriodEnd ?? fetchedAt.addingTimeInterval(7 * 24 * 3600)
        let used = min(max(config.creditUsagePercent, 0), 100)
        var windows: [UsageWindow] = [
            UsageWindow(kind: .weekly, used: used, limit: 100, unit: .percent, resetsAt: resetsAt)
        ]

        if config.onDemandCapCents > 0 {
            windows.append(
                UsageWindow(
                    kind: .custom,
                    used: Double(config.onDemandUsedCents),
                    limit: Double(config.onDemandCapCents),
                    unit: .credits,
                    resetsAt: resetsAt
                )
            )
        }

        return UsageSnapshot(
            providerID: .grok,
            fetchedAt: fetchedAt,
            windows: windows,
            models: []
        )
    }

    // MARK: - gRPC-web

    private static func unwrapGrpcWebMessage(_ body: Data) throws -> Data {
        var offset = 0
        var messages: [Data] = []
        while offset + 5 <= body.count {
            let flags = body[offset]
            let length = Int(body[offset + 1]) << 24
                | Int(body[offset + 2]) << 16
                | Int(body[offset + 3]) << 8
                | Int(body[offset + 4])
            offset += 5
            guard offset + length <= body.count else {
                throw GrokProviderError.transport("Malformed gRPC-web frame")
            }
            let payload = body.subdata(in: offset..<(offset + length))
            offset += length
            let isTrailer = (flags & 0x80) != 0
            if isTrailer {
                if let text = String(data: payload, encoding: .utf8) {
                    let lines = text.split(whereSeparator: \.isNewline)
                    if let statusLine = lines.first(where: {
                        $0.lowercased().hasPrefix("grpc-status:")
                    }) {
                        let status = statusLine
                            .split(separator: ":", maxSplits: 1)
                            .last?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if let status, status != "0" {
                            throw GrokProviderError.transport("gRPC status \(status)")
                        }
                    }
                }
            } else {
                messages.append(payload)
            }
        }
        guard let first = messages.first else {
            throw GrokProviderError.emptyUsage
        }
        if messages.count == 1 { return first }
        return messages.reduce(into: Data()) { $0.append($1) }
    }

    // MARK: - protobuf

    private enum Wire: Int {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case fixed32 = 5
    }

    private struct Field {
        var number: Int
        var wire: Wire
        var varint: UInt64 = 0
        var bytes: Data = Data()
        var fixed32BitPattern: UInt32 = 0
    }

    private static func fields(of data: Data) throws -> [Field] {
        var pos = 0
        var out: [Field] = []
        while pos < data.count {
            let (key, next) = try readVarint(data, pos)
            pos = next
            let number = Int(key >> 3)
            guard let wire = Wire(rawValue: Int(key & 0x7)) else {
                throw GrokProviderError.transport("Unsupported protobuf wire type")
            }
            switch wire {
            case .varint:
                let (value, npos) = try readVarint(data, pos)
                pos = npos
                out.append(Field(number: number, wire: wire, varint: value))
            case .fixed64:
                guard pos + 8 <= data.count else { throw GrokProviderError.transport("Truncated fixed64") }
                out.append(Field(number: number, wire: wire, bytes: data.subdata(in: pos..<(pos + 8))))
                pos += 8
            case .lengthDelimited:
                let (length, npos) = try readVarint(data, pos)
                pos = npos
                let len = Int(length)
                guard pos + len <= data.count else { throw GrokProviderError.transport("Truncated bytes") }
                out.append(Field(number: number, wire: wire, bytes: data.subdata(in: pos..<(pos + len))))
                pos += len
            case .fixed32:
                guard pos + 4 <= data.count else { throw GrokProviderError.transport("Truncated fixed32") }
                let pattern = UInt32(data[pos])
                    | UInt32(data[pos + 1]) << 8
                    | UInt32(data[pos + 2]) << 16
                    | UInt32(data[pos + 3]) << 24
                out.append(Field(number: number, wire: wire, fixed32BitPattern: pattern))
                pos += 4
            }
        }
        return out
    }

    private static func firstLengthDelimited(_ data: Data, field: Int) -> Data? {
        guard let match = try? fields(of: data).first(where: { $0.number == field && $0.wire == .lengthDelimited }) else {
            return nil
        }
        return match.bytes
    }

    private static func readVarint(_ data: Data, _ pos: Int) throws -> (UInt64, Int) {
        var value: UInt64 = 0
        var shift = 0
        var i = pos
        while true {
            guard i < data.count else { throw GrokProviderError.transport("Truncated varint") }
            let byte = data[i]
            i += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (value, i) }
            shift += 7
            if shift > 70 { throw GrokProviderError.transport("Varint too long") }
        }
    }

    private static func parseCent(_ message: Data) -> Int {
        guard !message.isEmpty else { return 0 }
        guard let fields = try? fields(of: message) else { return 0 }
        for field in fields where field.number == 1 {
            if field.wire == .varint { return Int(field.varint) }
        }
        return 0
    }

    private static func parseTimestamp(_ message: Data) -> Date? {
        guard let fields = try? fields(of: message) else { return nil }
        var seconds: Int64 = 0
        var nanos: Int32 = 0
        for field in fields {
            if field.number == 1, field.wire == .varint {
                seconds = Int64(bitPattern: field.varint)
            } else if field.number == 2, field.wire == .varint {
                nanos = Int32(truncatingIfNeeded: field.varint)
            }
        }
        guard seconds != 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanos) / 1_000_000_000)
    }
}

public enum GrokProviderError: Error, LocalizedError, Sendable, Equatable {
    case emptyUsage
    case httpStatus(Int)
    case transport(String)
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .emptyUsage:
            "Grok returned no usage data"
        case .httpStatus(let code):
            "Grok API HTTP \(code)"
        case .transport(let message):
            message
        case .notAuthenticated:
            "Grok is not connected"
        }
    }
}
