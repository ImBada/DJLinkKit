// 원본 metadata-connect/src/index.ts. TypeScript의 다시 내보내기(re-export)에 해당하는 것이 Swift에는 없으므로
// 이 파일은 metadata-connect가 내는 이름들을 한곳에 모으는 이름 공간(`MetadataConnect`)만 선언한다.
//
// alphatheta-connect의 `artwork/`가 같은 이름의 형(`FileReader`, `PictureType`)을 따로 내기 때문에
// metadata-connect 쪽은 모두 이 이름 공간 안에 둔다. 예: `MetadataConnect.FileReader`, `MetadataConnect.extractMetadata`.
// 원본 index.ts가 내보내던 것:
//   extractMetadata, getParserForExtension, getSupportedExtensions, isExtensionSupported, ExtractMetadataOptions,
//   FileReader, ExtractedMetadata, ArtworkMimeType, MetadataParser, PictureType, Logger, noopLogger,
//   createBufferReader, extractFromMp3, extractFromMp4, extractFromFlac, extractFromAiff, detectImageType, normalizeMimeType

/// metadata-connect 패키지의 이름 공간.
public enum MetadataConnect {}
