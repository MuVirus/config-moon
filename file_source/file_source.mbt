///|
/// 文件来源：一个路径加一个 `Format`。
///
/// 自己把文件读成字节，再交给格式解析；格式不知道数据来自磁盘。
/// 路径用字符串表示，和 `moonbitlang/x/fs` 的接口一致。
///
/// 读不到文件时抛 `ConfigError::IoError`，消息里带路径和底层原因；
/// 文件内容解析失败时仍由 `Format` 抛 `ConfigError::ParseError`。
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
/// 读文件；读不到时把路径和底层原因一起报出来
pub impl @config.Locator for FileSource with fn read(self : FileSource) -> Bytes raise @config.ConfigError {
  @fs.read_file_to_bytes(self.path) catch {
    @fs.IOError(message) =>
      raise @config.ConfigError::IoError("文件 \{self.path}：\{message}")
  }
}

///|
/// 文件内容交给格式解析
pub impl @config.Source for FileSource with fn collect(self : FileSource) -> @config.Value raise @config.ConfigError {
  self.format.decode(@config.Locator::read(self))
}

///|
/// 来源带 `Locator`：拿到 `origin` 后可以重新读同一个文件
pub impl @config.Source for FileSource with fn origin(self : FileSource) -> @config.Origin? {
  Some(@config.Origin::{
    kind: @config.SourceKind::File,
    label: "file:\{self.path}",
    locator: Some(self as &@config.Locator),
  })
}

///|
pub extend FileSource with @config.Locator::{read}

///|
pub extend FileSource with @config.Source::{collect, origin}
