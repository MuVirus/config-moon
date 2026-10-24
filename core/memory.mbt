///|
/// 内存来源：直接放进一个已经构造好的表。
///
/// 主要用来写默认值，也用来测合并规则——不碰任何 I/O，所有后端都能编。
pub struct MemorySource {
  table : Value
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
pub impl Source for MemorySource with fn collect(self : MemorySource) -> Value {
  self.table
}

///|
pub impl Source for MemorySource with fn origin(_ : MemorySource) -> Origin? {
  Some(Origin::new(SourceKind::Memory, "memory"))
}

///|
pub extend MemorySource with Source::{collect, origin}
