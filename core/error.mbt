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
    MissingKey(path) =>
      logger <+ "配置项 \{path} 不存在：没有任何来源提供它"
    TypeMismatch(path, expected, actual) =>
      logger <+
        "配置项 \{path} 类型不符：期望 \{expected}，实际 \{actual}"
    ParseError(message) => logger <+ "解析失败：\{message}"
    IoError(message) => logger <+ "读取失败：\{message}"
    MergeConflict(path, left, right) =>
      logger <+ "配置项 \{path} 合并冲突：\{left} 与 \{right}"
    InvalidValue(path, expected, actual) =>
      logger <+
        "配置项 \{path} 不符合约束：期望 \{expected}，实际 \{actual}"
    UnknownKey(path) => logger <+ "配置项 \{path} 不在允许的键里"
    UnknownFormat(name, suffixes) => {
      logger <+
        "无法判断 \{name} 的格式：后缀不认识，内容也不像任何候选"
      if !suffixes.is_empty() {
        logger <+ "；支持 "
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
