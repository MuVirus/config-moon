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
/// 用一段文本和一个格式构造来源
pub fn StringSource::new(text : String, format : &Format) -> StringSource {
  { text, format, }
}

///|
pub impl Source for StringSource with fn collect(self : StringSource) -> Value raise ConfigError {
  self.format.decode(@utf8.encode(self.text))
}

///|
pub impl Source for StringSource with fn origin(_ : StringSource) -> Origin? {
  Some(Origin::new(SourceKind::Custom, "string"))
}

///|
pub extend StringSource with Source::{collect, origin}
