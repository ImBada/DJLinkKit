func detectImageType(_ data: [UInt8]) -> ExtractedArtwork.MimeType? {
    if data.count < 4 {
        return nil
    }
    if data[0] == 0xff && data[1] == 0xd8 && data[2] == 0xff {
        return .jpeg
    }
    if data[0] == 0x89 && data.toString(.ascii, 1, 4) == "PNG" {
        return .png
    }
    if data.toString(.ascii, 0, 3) == "GIF" {
        return .gif
    }
    return nil
}

func normalizeMimeType(_ mimeType: String) -> ExtractedArtwork.MimeType {
    let lower = mimeType.lowercased()
    if lower.contains("png") {
        return .png
    }
    if lower.contains("gif") {
        return .gif
    }
    return .jpeg
}
