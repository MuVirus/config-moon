///|
/// 内存来源：直接塞一棵已经构造好的表。
///
/// 主要用来写默认值，也用来测合并规则——不碰任何 I/O，所有后端都能编。
pub struct MemorySource {
  table : Value
}

///|
/// 用一棵 `Value` 构造内存来源
pub fn MemorySource::new(table : Value) -> MemorySource {
  MemorySource::{ table, }
}

///|
pub impl Source for MemorySource with fn collect(self : MemorySource) -> Value {
  self.table
}

///|
pub extend MemorySource with Source::{collect}
