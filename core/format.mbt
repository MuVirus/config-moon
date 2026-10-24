///|
/// 解析器：把一段字节解成 `Value`。
///
/// 格式不知道数据从哪来——同一个 `JsonFormat` 既解析内存字符串，也解析文件内容。
/// 位置信息由 `Source` 负责，格式只做 `Bytes` → `Value`。
pub(open) trait Format {
  fn decode(Self, Bytes) -> Value raise ConfigError
}
