///|
/// 配置里的一条键路径，例如 `["db", "port"]`。
///
/// 点号串只在 API 边界解析一次，内部一直传结构化的段；展示时才拼回 `db.port`。
/// 和标准库的 `JsonPath` 是同一个思路：路径可以逐段拼，也可以整体格式化，但不靠字符串反解析。
pub struct KeyPath {
  priv segments : Array[String]
}

///|
/// 根路径，没有任何段
pub fn KeyPath::root() -> KeyPath {
  { segments: [], }
}

///|
/// 把点号路径拆成段：`"db.port"` → `["db", "port"]`
pub fn KeyPath::parse(text : String) -> KeyPath {
  { segments: text.split(".").map(fn(part) { part.to_owned() }).collect(), }
}

///|
/// 在末尾接一段，返回新路径；原路径不动
pub fn KeyPath::add(self : KeyPath, segment : String) -> KeyPath {
  let segments = self.segments.copy()
  segments.push(segment)
  { segments, }
}

///|
/// 按点号拼回展示用的路径
pub fn KeyPath::to_string(self : KeyPath) -> String {
  self.segments.join(".")
}

///|
/// 逐段访问，不复制
pub fn KeyPath::segments(self : KeyPath) -> ArrayView[String] {
  self.segments[:]
}

///|
pub fn KeyPath::is_empty(self : KeyPath) -> Bool {
  self.segments.is_empty()
}
