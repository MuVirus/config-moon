///|
/// 库的错误类型。
///
/// 唯一的体验标准：用户看到错误，能立刻知道**哪个键、期望什么、实际什么**。
pub(all) suberror ConfigError {
  MissingKey(String) // 路径没被任何来源提供
  TypeMismatch(String, String, String) // 路径、期望、实际
  ParseError(String) // 文本解析失败（包住 @json 的错误）
  IoError(String) // 读取外部数据失败（文件、环境变量……）
  MergeConflict(String, String, String) // 类型冲突：路径、两侧类型
  InvalidValue(String, String, String) // 校验失败：路径、期望约束、实际
  UnknownKey(String) // 校验时发现不在允许列表里的键
  UnknownFormat(String, Array[String]) // 无法判断格式：名称、支持的后缀
} derive(Eq, @debug.Debug)

///|
/// 报错时给人看的消息：哪个键、期望什么、实际什么。
pub impl Show for ConfigError with fn output(self, logger) {
  match self {
    MissingKey(path) => logger <+ "missing key '\{path}': no source provides it"
    TypeMismatch(path, expected, actual) =>
      logger <+ "key '\{path}': expected \{expected}, got \{actual}"
    ParseError(message) => logger <+ "parse error: \{message}"
    IoError(message) => logger <+ "read error: \{message}"
    MergeConflict(path, left, right) =>
      logger <+ "merge conflict at key '\{path}': \{left} vs \{right}"
    InvalidValue(path, expected, actual) =>
      logger <+
        "invalid value for key '\{path}': expected \{expected}, got \{actual}"
    UnknownKey(path) => logger <+ "key '\{path}' is not allowed"
    UnknownFormat(name, suffixes) => {
      logger <+
        "unknown format for \{name}: suffix not recognized and content matches no candidate"
      if !suffixes.is_empty() {
        logger <+ "; supported suffixes: "
        for i, suffix in suffixes {
          if i > 0 {
            logger <+ " / "
          }
          logger <+ ".\{suffix}"
        }
      }
    }
  }
}

///|
/// `derive` 生成的 `impl` 不再自动变成方法，需要显式挂上去。
pub extend ConfigError with Show::{output, to_string}

///|
pub extend ConfigError with Eq::{equal, not_equal}

///|
pub extend ConfigError with @debug.Debug::{to_repr}
