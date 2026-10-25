///|
/// 内存来源：直接放进一个已经构造好的表。
///
/// 主要用来写默认值，也用来测合并规则——不碰任何 I/O，所有后端都能编。
pub struct MemorySource {
  table : Value
}

///|
/// 内存来源的 site。
///
/// 单独一个空对象，不返回 `MemorySource` 自己：`MemorySource` 持有值树，
/// 值树再指回它就成了环，而 native 默认的引用计数不回收环。
priv struct MemorySite {}

///|
impl OriginSite for MemorySite with fn kind(_ : MemorySite) -> SourceKind {
  SourceKind::Memory
}

///|
impl OriginSite for MemorySite with fn describe(_ : MemorySite, _ : KeyPath) -> String {
  "memory"
}

///|
/// 用一个 `Value` 构造内存来源
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = Config::new()
///     .add(MemorySource::new(Value::table({ "debug": Value::bool(false) })))
///     .build()
///   assert_false(cfg.get_bool("debug"))
/// }
/// ```
pub fn MemorySource::new(table : Value) -> MemorySource {
  MemorySource::{ table, }
}

///|
pub impl Source for MemorySource with fn collect(self : MemorySource) -> Layer {
  Layer::new(self.table, Some(MemorySite::{ } as &OriginSite))
}

///|
pub impl Source for MemorySource with fn kind(_ : MemorySource) -> SourceKind {
  SourceKind::Memory
}

///|
pub extend MemorySource with Source::{collect, kind, raw_locator}
