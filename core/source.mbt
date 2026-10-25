///|
/// 一层来源读出来的东西：一棵值，加上这层的来源对象。
///
/// `origin` 为 `None` 时这层不参与追踪；大多数来源都会给一个 `OriginSite`。
/// 环境变量、命令行把整层共用的来源对象放在这里，由它按路径回答具体是哪个变量。
pub struct Layer {
  value : Value
  origin : &OriginSite?
}

///|
/// 一层值加它的来源
pub fn Layer::new(value : Value, origin : &OriginSite?) -> Layer {
  { value, origin, }
}

///|
/// 一层不追踪来源的值
pub fn Layer::untracked(value : Value) -> Layer {
  { value, origin: None, }
}

///|
/// 来源：能把一份配置读成一层的对象。
///
/// 这是核心唯一的扩展点。所有具体来源（内存、文件、环境变量……）
/// 都实现这个 trait，再交给 `Config::add`。
pub(open) trait Source {
  fn collect(Self) -> Layer raise ConfigError
  /// 合并规则按它排序；默认归到 `Custom`。
  fn kind(Self) -> SourceKind = _
}

///|
/// 默认是自定义来源
impl Source with fn kind(_) {
  SourceKind::Custom
}
