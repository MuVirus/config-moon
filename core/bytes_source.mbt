///|
/// 字节来源：一段字节加一个 `Format`。
///
/// 给二进制格式用，比如 CBOR。文本格式也能走这里，只是调用方得自己编码。
pub struct BytesSource {
  bytes : Bytes
  format : &Format
}

///|
/// 用一段字节和一个格式构造来源
pub fn BytesSource::new(bytes : Bytes, format : &Format) -> BytesSource {
  { bytes, format, }
}

///|
pub impl Source for BytesSource with fn collect(self : BytesSource) -> Value raise ConfigError {
  self.format.decode(self.bytes)
}

///|
pub impl Source for BytesSource with fn origin(_ : BytesSource) -> Origin? {
  Some(Origin::new(SourceKind::Custom, "bytes"))
}

///|
pub extend BytesSource with Source::{collect, origin}
