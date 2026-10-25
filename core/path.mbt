///|
/// 路径相关的一切都放这里。
///
/// 路径用点号展开：`"db.host"` → `Table{"db": Table{"host": ...}}`。
/// 内部走结构化的 `KeyPath`，点号串只在 API 边界解析一次。
/// 以后要加通配符（`db.*`）或者写入（`set`），也是这个文件的事。

///|
/// 按点号路径取值
///
/// key 不存在就报错，不返回默认值——默认值是 `MemorySource` 的职责。
pub fn Value::get_path(self : Value, path : String) -> Value raise ConfigError {
  self.get_at(KeyPath::parse(path))
}

///|
/// 按已经拆好的路径取值
pub fn Value::get_at(self : Value, path : KeyPath) -> Value raise ConfigError {
  let mut cur = self
  for segment in path.segments() {
    cur = match cur.kind {
      ValueKind::Table(t) =>
        match t.get(segment) {
          Some(v) => v
          None => raise ConfigError::MissingKey(path.to_string())
        }
      _ =>
        raise ConfigError::TypeMismatch(
          path.to_string(),
          "Table",
          cur.kind.name(),
        )
    }
  }
  cur
}
