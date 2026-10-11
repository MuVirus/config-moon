///|
/// 来源：能把一份配置变成一棵 `Value` 的东西。
///
/// 这是核心唯一的扩展点。所有具体来源（内存、JSON、文件、环境变量……）
/// 都实现这个 trait，再交给 `Config::add`。
pub(open) trait Source {
  fn collect(Self) -> Value raise ConfigError
}
