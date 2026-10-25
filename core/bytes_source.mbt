///|
/// 字节来源：一段字节加一个 `Format`。
///
/// 给二进制格式用，比如 CBOR。文本格式也能走这里，只是调用方得自己编码。
pub struct BytesSource {
  bytes : Bytes
  format : &Format
}

///|
/// `BytesSource` 的 site：只说明这层来自一段字节
priv struct BytesSite {}

///|
impl OriginSite for BytesSite with fn kind(_ : BytesSite) -> SourceKind {
  SourceKind::Custom
}

///|
impl OriginSite for BytesSite with fn describe(_ : BytesSite, _ : KeyPath) -> String {
  "bytes"
}

///|
/// 用一段字节和一个格式构造来源
pub fn BytesSource::new(bytes : Bytes, format : &Format) -> BytesSource {
  { bytes, format, }
}

///|
pub impl Source for BytesSource with fn collect(self : BytesSource) -> Layer raise ConfigError {
  Layer::new(
    self.format.decode(self.bytes),
    Some(BytesSite::{ } as &OriginSite),
  )
}

///|
pub impl Source for BytesSource with fn kind(_ : BytesSource) -> SourceKind {
  SourceKind::Custom
}

///|
pub extend BytesSource with Source::{collect, kind, raw_locator}
