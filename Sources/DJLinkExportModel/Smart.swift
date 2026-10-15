// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbxport/crates/rbl-index/src/smart.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// 원본의 규칙 파싱·평가·날짜 정규화를 옮겼다.
import Foundation

public enum Logic: Equatable, Sendable { case all, any }
public enum Operator: String, Sendable {
    case equal = "1"
    case notEqual = "2"
    case greater = "3"
    case less = "4"
    case inRange = "5"
    case inLast = "6"
    case notInLast = "7"
    case contains = "8"
    case notContains = "9"
    case startsWith = "10"
    case endsWith = "11"
    public func code() -> String { rawValue }
    public static func from_code(_ code: String) -> Self? {
        Int32(modelTrim(code)).flatMap { Self(rawValue: String($0)) }
    }
}
public enum Property: String, Sendable {
    case artist = "artist"
    case album = "album"
    case albumArtist = "albumArtist"
    case originalArtist = "originalArtist"
    case composer = "producer"
    case remixer = "remixedBy"
    case mixName = "mixName"
    case genre = "genre"
    case label = "label"
    case key = "key"
    case title = "name"
    case comment = "comments"
    case fileName = "fileName"
    case bpm = "bpm"
    case rating = "rating"
    case color = "grouping"
    case playCount = "counter"
    case duration = "duration"
    case year = "year"
    case dateAdded = "stockDate"
    case dateCreated = "dateCreated"
    case dateReleased = "dateReleased"
    case myTag = "myTag"
    case unsupported = ""
    public func name() -> String { rawValue }
    public static func from_name(_ name: String) -> Self {
        all.first { ascii_equal($0.rawValue, name) } ?? .unsupported
    }
    private static let all: [Self] = [
        .artist, .album, .albumArtist, .originalArtist, .composer, .remixer, .mixName, .genre, .label, .key, .title,
        .comment, .fileName, .bpm, .rating, .color, .playCount, .duration, .year, .dateAdded, .dateCreated,
        .dateReleased, .myTag,
    ]
}
public struct Condition: Equatable, Sendable {
    public var property: Property
    public var `operator`: Operator
    public var left: String
    public var right: String
    public var unit: String
    public init(property: Property, `operator`: Operator, left: String, right: String = "", unit: String = "") {
        self.property = property
        self.operator = `operator`
        self.left = left
        self.right = right
        self.unit = unit
    }
    public static func from_editor(
        _ property: Property, _ op: Operator, _ left: String, _ right: String, _ unit: String
    ) -> Self {
        switch property {
        case .bpm:
            return Self(
                property: property, operator: op, left: bpm_to_stored(left), right: bpm_to_stored(right),
                unit: bpm_to_stored(unit))
        case .rating where op != .inRange:
            return Self(property: property, operator: op, left: left, right: "0", unit: unit)
        default: return Self(property: property, operator: op, left: left, right: right, unit: unit)
        }
    }
    public func editor_values() -> (String, String, String) {
        switch property {
        case .bpm: return (bpm_for_editor(left), `operator` == .inRange ? bpm_for_editor(right) : "", "")
        case .rating where `operator` != .inRange: return (left, "", unit)
        default: return (left, right, unit)
        }
    }
}
public struct Group: Equatable, Sendable {
    public var logic: Logic
    public var items: [Item]
    public init(logic: Logic, items: [Item]) {
        self.logic = logic
        self.items = items
    }
}
public indirect enum Item: Equatable, Sendable { case condition(Condition), group(Group) }
public struct SmartRule: Equatable, Sendable {
    public var root: Group
    public init(root: Group) { self.root = root }
    public static func parse(_ xml: String) -> Self? {
        guard let document = smart_document(xml) else { return nil }
        let elements = tags(document)
        guard let first = elements.first, case .open(let name, let attributes, let closed) = first,
            ascii_equal(name, "NODE")
        else { return nil }
        var root = Group(
            logic: Int32(modelTrim(smart_attribute(attributes, "LogicalOperator"))) == 2 ? .any : .all, items: [])
        if closed { return Self(root: root) }
        var open = [name]
        for tag in elements.dropFirst() {
            switch tag {
            case .open(let name, let attributes, let closed):
                if open.count == 1 && ascii_equal(name, "CONDITION"),
                    let op = Operator.from_code(smart_attribute(attributes, "Operator"))
                {
                    root.items.append(
                        .condition(
                            Condition(
                                property: Property.from_name(smart_attribute(attributes, "PropertyName")), operator: op,
                                left: smart_attribute(attributes, "ValueLeft"),
                                right: smart_attribute(attributes, "ValueRight"),
                                unit: smart_attribute(attributes, "ValueUnit"))))
                }
                if !closed { open.append(name) }
            case .close(let name):
                // 원본은 마지막 루트 닫기 태그 이름을 검사하지 않는다.
                if open.count == 1 { return Self(root: root) }
                guard let opened = open.popLast(), ascii_equal(opened, name) else { return nil }
            }
        }
        return nil
    }
    public func to_xml(_ id: UInt64) -> String {
        func write_group(_ group: Group, _ id: UInt64?) -> String {
            let logic = group.logic == .all ? "1" : "2"
            var out =
                id.map {
                    "<NODE Id=\"\(Int32(bitPattern: UInt32(truncatingIfNeeded: $0)))\" LogicalOperator=\"\(logic)\" AutomaticUpdate=\"0\""
                } ?? "<NODE LogicalOperator=\"\(logic)\""
            if group.items.isEmpty { return out + "/>" }
            out += ">"
            for item in group.items {
                switch item {
                case .condition(let c):
                    out +=
                        "<CONDITION PropertyName=\"\(c.property.name())\" Operator=\"\(c.operator.code())\" ValueUnit=\"\(escape_attribute(c.unit))\" ValueLeft=\"\(escape_attribute(c.left))\" ValueRight=\"\(escape_attribute(c.right))\"/>"
                case .group(let g): out += write_group(g, nil)
                }
            }
            return out + "</NODE>"
        }
        return write_group(root, id)
    }
    public func unsupported() -> Int {
        func count(_ group: Group) -> Int {
            group.items.reduce(0) { result, item in
                switch item {
                case .condition(let c): return result + (c.property == .unsupported ? 1 : 0)
                case .group(let g): return result + count(g)
                }
            }
        }
        return count(root)
    }
    public func evaluate(_ library: Library) -> [Row] { evaluate_on(library, SmartDate.today()) }
    public func evaluate_on(_ library: Library, _ today: SmartDate) -> [Row] {
        let compiled = CompiledGroup(root, library, today)
        return (0..<library.len()).compactMap(Row.init(exactly:)).filter { compiled.matches(library, $0) }
    }
}
private func smart_attribute(_ attributes: [(String, String)], _ name: String) -> String {
    attributes.first { $0.0.utf8.elementsEqual(name.utf8) }?.1 ?? ""
}
private func smart_document(_ xml: String) -> String? {
    var rest = xml[...]
    while true {
        rest = modelTrim(String(rest), end: false)[...]
        if rest.hasPrefix("<!--") {
            let after = rest.dropFirst(4)
            guard let end = after.range(of: "-->") else { return nil }
            rest = after[end.upperBound...]
            continue
        }
        if rest.hasPrefix("<?") {
            let after = rest.dropFirst(2)
            guard let end = after.range(of: "?>") else { return nil }
            rest = after[end.upperBound...]
            continue
        }
        return rest.hasPrefix("<") ? String(rest) : nil
    }
}
public func escape_attribute(_ text: String) -> String {
    var out = ""
    for c in text.unicodeScalars {
        switch c {
        case "\"": out += "&quot;"
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        default:
            if (32...126).contains(c.value) && c != "^" && c != "`" {
                out.unicodeScalars.append(c)
            } else {
                out += "&#\(c.value);"
            }
        }
    }
    return out
}
public func my_tag_key(_ text: String) -> Int32 {
    var chars = Array(text.unicodeScalars.drop(while: { $0.properties.isWhitespace }))
    var negative = false
    if chars.first == "-" {
        negative = true
        chars.removeFirst()
    } else if chars.first == "+" {
        chars.removeFirst()
    }
    var value: Int32 = 0
    for c in chars {
        guard (48...57).contains(c.value) else { break }
        value = value &* 10 &+ Int32(c.value - 48)
    }
    return negative ? 0 &- value : value
}
public func bpm_to_stored(_ text: String) -> String {
    let bytes = Array(text.utf8)
    guard let point = bytes.firstIndex(of: 46) else { return String(my_tag_key(text) &* 100) }
    let whole = my_tag_key(String(decoding: bytes[..<point], as: UTF8.self))
    func digit(_ at: Int) -> Int32 {
        guard let byte = bytes.at(at), String(bytes: [byte], encoding: .utf8) != nil else { return 0 }
        return my_tag_key(String(decoding: [byte], as: UTF8.self))
    }
    return String(whole &* 100 &+ digit(point + 1) &* 10 &+ digit(point + 2))
}
public func bpm_for_editor(_ stored: String) -> String {
    let value = Int64(my_tag_key(stored))
    let sign = value < 0 ? "-" : ""
    let whole = abs(value) / 100
    let h = abs(value) % 100
    if h == 0 { return "\(sign)\(whole)" }
    if h % 10 == 0 { return "\(sign)\(whole).\(h / 10)" }
    return "\(sign)\(whole).\(String(format: "%02lld", h))"
}
private struct CompiledGroup {
    var logic: Logic
    var items: [CompiledItem]
    init(_ group: Group, _ library: Library, _ today: SmartDate) {
        logic = group.logic
        items = group.items.map {
            switch $0 {
            case .condition(let c): return .condition(CompiledCondition(c, library, today))
            case .group(let g): return .group(CompiledGroup(g, library, today))
            }
        }
    }
    func matches(_ library: Library, _ row: Row) -> Bool {
        !items.isEmpty
            && (logic == .all
                ? items.allSatisfy { $0.matches(library, row) } : items.contains { $0.matches(library, row) })
    }
}
private indirect enum CompiledItem {
    case condition(CompiledCondition), group(CompiledGroup)
    func matches(_ library: Library, _ row: Row) -> Bool {
        switch self {
        case .condition(let c): return c.matches(library, row)
        case .group(let g): return g.matches(library, row)
        }
    }
}
struct CompiledCondition {
    var property: Property
    var op: Operator
    var text: String
    var low: Int64 = 0
    var high: Int64 = 0
    var date_bounds_valid = true
    init(_ condition: Condition, _ library: Library, _ today: SmartDate) {
        property = condition.property
        op = condition.operator
        text = fold_smart(property == .key ? modelTrim(condition.left) : condition.left)
        switch property {
        case .bpm, .rating, .playCount, .year:
            low = whole(condition.left)
            high = whole(condition.right)
        case .duration:
            low = seconds(condition.left)
            high = seconds(condition.right)
        case .color:
            low = Int64(my_tag_key(condition.left))
            high = Int64(my_tag_key(condition.right))
        case .myTag: low = Int64(my_tag_key(condition.left))
        case .dateAdded, .dateCreated, .dateReleased:
            switch op {
            case .inLast, .notInLast:
                low = today.minus(relative_count(condition.left), condition.unit).days()
                high = today.days()
            case .inRange:
                let a = smart_date(condition.left)
                let b = smart_date(condition.right)
                date_bounds_valid = a != nil && b != nil
                low = a ?? 0
                high = b ?? 0
            default:
                let a = smart_date(condition.left)
                date_bounds_valid = a != nil
                low = a ?? 0
            }
        default: break
        }
        _ = library
    }
    func matches(_ lib: Library, _ row: Row) -> Bool {
        let index = Int(row)
        switch property {
        case .artist: return text_matches(lib.artist_name(row))
        case .album: return text_matches(lib.album_name(row))
        case .albumArtist: return text_matches(lib.search_extra[1].get(index))
        case .originalArtist: return text_matches(lib.search_extra[3].get(index))
        case .composer: return text_matches(lib.search_extra[0].get(index))
        case .remixer: return text_matches(lib.search_extra[2].get(index))
        case .mixName: return text_matches(lib.search_extra[4].get(index))
        case .genre: return text_matches(lib.genre_name(row))
        case .label: return text_matches(lib.label_name(row))
        case .key: return text_matches(lib.key_name(row))
        case .title: return text_matches(lib.title.get(index))
        case .comment: return text_matches(lib.comment.get(index))
        case .fileName: return text_matches(lib.file_name.get(index))
        case .bpm: return number_matches(Int64(lib.bpm_x100.at(index) ?? 0))
        case .rating: return number_matches(Int64(lib.rating.at(index) ?? 0))
        case .color: return number_matches(Int64(lib.color.at(index) ?? 0))
        case .playCount: return number_matches(Int64(lib.play_count.at(index) ?? 0))
        case .duration: return number_matches(Int64(lib.length_sec.at(index) ?? 0))
        case .year: return number_matches(Int64(lib.year.at(index) ?? 0))
        // 원본 dateCreated 조건도 date_added를 읽는다.
        case .dateAdded, .dateCreated: return date_matches(lib.date_added.get(index))
        case .dateReleased: return date_matches(lib.release_date.get(index))
        case .myTag: return tag_matches(lib.my_tag_keys(index))
        case .unsupported: return false
        }
    }
    func text_matches(_ value: String) -> Bool {
        let folded = Array(fold_smart(value).utf8)
        let wanted = Array(text.utf8)
        func contains() -> Bool {
            if wanted.isEmpty { return true }
            guard wanted.count <= folded.count else { return false }
            return (0...(folded.count - wanted.count)).contains { Array(folded[$0..<$0 + wanted.count]) == wanted }
        }
        switch op {
        case .equal: return folded == wanted
        case .notEqual: return folded != wanted
        case .contains: return !folded.isEmpty && !wanted.isEmpty && contains()
        case .notContains: return !folded.isEmpty && !wanted.isEmpty && !contains()
        case .startsWith: return !folded.isEmpty && !wanted.isEmpty && folded.starts(with: wanted)
        case .endsWith: return !folded.isEmpty && !wanted.isEmpty && folded.suffix(wanted.count).elementsEqual(wanted)
        default: return false
        }
    }
    func number_matches(_ value: Int64) -> Bool {
        switch op {
        case .equal: return value == low
        case .notEqual: return value != low
        case .greater: return value > low
        case .less: return value < low
        case .inRange: return value >= low && value <= high
        default: return false
        }
    }
    func tag_matches(_ keys: [Int32]) -> Bool {
        let wanted = Int32(exactly: low) ?? 0
        switch op {
        case .contains: return keys.contains(wanted)
        case .notContains: return !keys.contains(wanted)
        default: return false
        }
    }
    func date_matches(_ value: String) -> Bool {
        guard let days = smart_date(value) else { return false }
        if !date_bounds_valid { return op == .notEqual }
        switch op {
        case .equal: return days == low
        case .notEqual: return days != low
        case .greater: return days > low
        case .less, .notInLast: return days < low
        case .inRange: return days >= low && days <= high
        case .inLast: return days >= low
        default: return false
        }
    }
}
func whole(_ text: String) -> Int64 {
    let value = Double(modelTrim(text)) ?? 0
    if value.isNaN { return 0 }
    return Int64(min(max(value.rounded(.towardZero), Double(Int32.min)), Double(Int32.max)))
}
func seconds(_ text: String) -> Int64 {
    let text = modelTrim(text)
    let bytes = Array(text.utf8)
    if let point = bytes.firstIndex(of: 58) {
        return whole(String(decoding: bytes[..<point], as: UTF8.self)) * 60
            + whole(String(decoding: bytes.dropFirst(point + 1), as: UTF8.self))
    }
    return whole(text)
}
private func euclid_div(_ a: Int64, _ b: Int64) -> Int64 {
    let q = a / b
    let r = a % b
    return r < 0 ? q - 1 : q
}
private func euclid_rem(_ a: Int64, _ b: Int64) -> Int64 {
    let r = a % b
    return r < 0 ? r + b : r
}
func smart_date(_ text: String) -> Int64? {
    let chars = Array(text.unicodeScalars)
    guard chars.count == 10 && !chars.contains("\0") else { return nil }
    func positional(_ range: Range<Int>) -> Int64 { range.reduce(0) { $0 * 10 + Int64(chars[$1].value) - 48 } }
    let year = positional(0..<4)
    let month = positional(5..<7)
    let day = positional(8..<10)
    let total = year * 12 + month - 1
    let normalized_year = euclid_div(total, 12)
    let normalized_month = euclid_rem(total, 12) + 1
    let days = days_from_civil(normalized_year, normalized_month, 1) + day - 1
    let normalized = SmartDate.from_days(days)
    return days > 0 && normalized.year <= 3000 ? days : nil
}
public struct SmartDate: Equatable, Sendable {
    public var year: Int64
    public var month: Int64
    public var day: Int64
    public init(year: Int64, month: Int64, day: Int64) {
        self.year = year
        self.month = month
        self.day = day
    }
    public static func today() -> Self {
        let values = Calendar.current.dateComponents([.year, .month, .day], from: Foundation.Date())
        return Self(year: Int64(values.year ?? 1970), month: Int64(values.month ?? 1), day: Int64(values.day ?? 1))
    }
    public static func parse(_ text: String) -> Self? {
        let bytes = Array(modelTrim(text).utf8)
        guard bytes.count >= 10, let text = String(bytes: bytes.prefix(10), encoding: .utf8) else { return nil }
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 3, let year = Int64(parts[0]), let month = Int64(parts[1]), let day = Int64(parts[2]),
            (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        return Self(year: year, month: month, day: day)
    }
    public func days() -> Int64 { days_from_civil(year, month, day) }
    public func minus(_ count: Int64, _ unit: String) -> Self {
        if ascii_equal(unit, "month") { return months_back(count) }
        return days_ago(max(count, 1) - 1)
    }
    public func days_ago(_ count: Int64) -> Self { Self.from_days(days() - count) }
    func months_back(_ count: Int64) -> Self {
        let total = year * 12 + month - 1 - max(count, 1) + 1
        return Self.from_days(days_from_civil(euclid_div(total, 12), euclid_rem(total, 12) + 1, 1) - 1)
    }
    static func from_days(_ days: Int64) -> Self {
        let (year, month, day) = civil_from_days(days)
        return Self(year: year, month: month, day: day)
    }
}
public enum Smart { public typealias Date = SmartDate }
private func days_from_civil(_ year: Int64, _ month: Int64, _ day: Int64) -> Int64 {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = month > 2 ? month - 3 : month + 9
    let doy = (153 * mp + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
}
private func civil_from_days(_ days: Int64) -> (Int64, Int64, Int64) {
    let z = days + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
    let y = yoe + era * 400
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let d = doy - (153 * mp + 2) / 5 + 1
    let m = mp < 10 ? mp + 3 : mp - 9
    return (m <= 2 ? y + 1 : y, m, d)
}

func relative_count(_ text: String) -> Int64 { max(Int64(modelTrim(text)) ?? 0, 0) }
func color_id(_ text: String) -> Int64 { Int64(my_tag_key(text)) }
