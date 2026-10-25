///|
/// 文件来源：一个路径加一个 `Format`。
///
/// 自己把文件读成字节，再交给格式解析；格式不知道数据来自磁盘。
/// 路径用字符串表示，和 `moonbitlang/x/fs` 的接口一致。
///
/// 读不到文件时抛 `ConfigError::IoError`，消息里带路径和底层原因；
/// 文件内容解析失败时仍由 `Format` 抛 `ConfigError::ParseError`。
///
/// `FileSource` 同时是这层的 `OriginSite`：标签是文件路径，`locator` 就是它自己，
/// 拿到 `origin` 后可以重新读同一个文件。
pub struct FileSource {
  path : String
  format : &@config.Format
}

///|
/// 用路径和格式构造文件来源
pub fn FileSource::new(path : String, format : &@config.Format) -> FileSource {
  { path, format, }
}

///|
/// 用路径和自动检测器构造文件来源：后缀认识走后缀，否则看内容。
///
/// 后缀认识却解析失败时直接报错，不会偷偷换一个格式重试。
pub fn FileSource::auto(
  path : String,
  detector : @format_detect.Detector,
) -> FileSource {
  { path, format: detector as &@config.Format }
}

///|
/// 读文件；读不到时把路径和底层原因一起报出来
pub impl @config.Locator for FileSource with fn read(self : FileSource) -> Bytes raise @config.ConfigError {
  @fs.read_file_to_bytes(self.path) catch {
    @fs.IOError(message) =>
      raise @config.ConfigError::IoError("文件 \{self.path}：\{message}")
  }
}

///|
/// 文件来源的标签就是文件路径
pub impl @config.OriginSite for FileSource with fn kind(_ : FileSource) -> @config.SourceKind {
  @config.SourceKind::File
}

///|
pub impl @config.OriginSite for FileSource with fn describe(
  self : FileSource,
  _ : @config.KeyPath,
) -> String {
  "file:\{self.path}"
}

///|
/// 文件来源能反推原始字节
pub impl @config.OriginSite for FileSource with fn locator(self : FileSource) -> &@config.Locator? {
  Some(self as &@config.Locator)
}

///|
/// 文件内容交给格式解析
pub impl @config.Source for FileSource with fn collect(self : FileSource) -> @config.Layer raise @config.ConfigError {
  let bytes = @config.Locator::read(self)
  let value = self.format.decode_path(self.path, bytes)
  @config.Layer::new(value, Some(self as &@config.OriginSite))
}

///|
pub impl @config.Source for FileSource with fn kind(_ : FileSource) -> @config.SourceKind {
  @config.SourceKind::File
}

///|
/// 文件来源知道自己能反推原始字节
pub impl @config.Source for FileSource with fn raw_locator(self : FileSource) -> &@config.Locator? {
  Some(self as &@config.Locator)
}

///|
pub extend FileSource with @config.Locator::{read}

///|
pub extend FileSource with @config.OriginSite::{describe, locator}

///|
pub extend FileSource with @config.Source::{collect, kind, raw_locator}
