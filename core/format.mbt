///|
/// 解析器：把一段字节解成 `Value`。
///
/// 格式不知道数据从哪来——同一个 `JsonFormat` 既解析内存字符串，也解析文件内容。
/// 位置信息由 `Source` 负责，格式只做 `Bytes` → `Value`。
///
/// `suffixes` 和 `sniff` 是自动发现用的自我介绍，都有默认实现：
/// 不声明就表示「只认后缀，不参与内容判断」。
pub(open) trait Format {
  fn decode(Self, Bytes) -> Value raise ConfigError
  /// 认哪些后缀（不带点），默认一个都不认
  fn suffixes(Self) -> Array[String] = _
  /// 内容像不像这种格式，默认不像
  fn sniff(Self, Bytes) -> Bool = _
  /// 知道路径时先看后缀；普通格式默认忽略路径
  fn decode_path(Self, String, Bytes) -> Value raise ConfigError = _
}

///|
/// 默认不声明任何后缀
impl Format with fn suffixes(_) {
  []
}

///|
/// 默认不参与内容判断
impl Format with fn sniff(_, _) {
  false
}

///|
/// 默认忽略路径，按内容解析
impl Format with fn decode_path(self, _, bytes) {
  self.decode(bytes)
}
