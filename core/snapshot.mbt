///|
/// 配置快照里的一条：路径、值，以及它最终的来源。
///
/// `origin` 是 `None` 表示这层来源没有追踪信息（`Layer::untracked`），
/// 不是「没有这个键」。
pub struct Entry {
  priv path : KeyPath
  priv value : Value
  priv origin : Origin?
}

///|
/// 这条配置的层级路径
pub fn Entry::path(self : Entry) -> KeyPath {
  self.path
}

///|
/// 这条配置的值
pub fn Entry::value(self : Entry) -> Value {
  self.value
}

///|
/// 这条配置最终的来源；来源未追踪时给 `None`
pub fn Entry::origin(self : Entry) -> Origin? {
  self.origin
}

///|
/// 导出带来源的配置快照：每个叶子一条，路径、值、来源一起给。
///
/// 叶子口径和 `origins()` 一致：表节点递归往下，数组整体当叶子。
/// 来源未追踪时 `origin()` 给 `None`。
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = @config.Config::new()
///     .add(
///       @config.MemorySource::new(
///         @config.Value::table({ "debug": @config.Value::bool(false) }),
///       ),
///     )
///     .build()
///   let entries = cfg.snapshot()
///   assert_eq(entries.length(), 1)
///   assert_eq(entries[0].path().to_string(), "debug")
/// }
/// ```
pub fn Config::snapshot(self : Config) -> Array[Entry] raise ConfigError {
  let result : Array[Entry] = []
  collect_entries(self.merged(), KeyPath::root(), result)
  result
}

///|
/// 遍历整棵树收叶子；表节点继续往下，数组和标量都是叶子。
fn collect_entries(
  value : Value,
  path : KeyPath,
  result : Array[Entry],
) -> Unit {
  match value.kind {
    ValueKind::Table(table) =>
      for key, child in table {
        collect_entries(child, path.add(key), result)
      }
    _ => {
      let origin = match value.origin {
        Some(site) => Some(Origin::{ site, path, })
        None => None
      }
      result.push(Entry::{ path, value, origin, })
    }
  }
}
