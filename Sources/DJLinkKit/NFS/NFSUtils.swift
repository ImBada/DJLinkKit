/// 원본 linked list를 배열로 바꾸는 도우미. nil 루트는 원본처럼 유효한 노드가 아니다.
public func flattenLinkedList<T>(_ item: T, next: (T) -> T?) -> [T] {
    var result: [T] = []
    var current: T? = item
    while let node = current {
        result.append(node)
        current = next(node)
    }
    return result
}
