///|
/// 字符串来源：一段文本加一个 `Format`。
///
/// 文本先编码成字节，再交给 `Format::decode`。来源不知道格式是什么，
/// 格式也不知道文本从哪来。
pub struct StringSource {
  text : String
  format : &Format
}

///|
/// `StringSource` 的 site：只说明这层来自一段文本
priv struct StringSite {}

///|
impl OriginSite for StringSite with fn kind(_ : StringSite) -> SourceKind {
  SourceKind::Custom
}

///|
impl OriginSite for StringSite with fn describe(_ : StringSite, _ : KeyPath) -> String {
  "string"
}

///|
/// 用一段文本和一个格式构造来源
pub fn StringSource::new(text : String, format : &Format) -> StringSource {
  { text, format, }
}

///|
pub impl Source for StringSource with fn collect(self : StringSource) -> Layer raise ConfigError {
  Layer::new(
    self.format.decode(@utf8.encode(self.text)),
    Some(StringSite::{ } as &OriginSite),
  )
}

///|
pub impl Source for StringSource with fn kind(_ : StringSource) -> SourceKind {
  SourceKind::Custom
}

///|
pub extend StringSource with Source::{collect, kind}
