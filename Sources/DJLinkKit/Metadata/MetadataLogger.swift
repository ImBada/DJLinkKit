import Foundation

// 원본 metadata-connect/src/types/logger.ts. 기반의 `Logger`(Logger.swift)와 모양이 같아 그것을 그대로 쓴다.
extension MetadataConnect {
    /// Logger interface for metadata-connect. Allows consumers to inject their own logger implementation.
    public typealias Logger = DJLinkKit.Logger

    public static let noopLogger: any Logger = DJLinkKit.noopLogger
}
