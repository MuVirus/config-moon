///|
/// 路径相关的一切都放这里。
///
/// 路径用点号展开：`"db.host"` → `Table{"db": Table{"host": ...}}`。
/// 以后要加通配符（`db.*`）或者写入（`set`），也是这个文件的事。

///|
/// 按点号路径取值
///
/// key 不存在就报错，不返回默认值——默认值是 `MemorySource` 的职责。
pub fn Value::get_path(self : Value, path : String) -> Value raise ConfigError {
  let mut cur = self
  for part in path.split(".") {
    let key = part.to_owned()
    cur = match cur.kind {
      ValueKind::Table(t) =>
        match t.get(key) {
          Some(v) => v
          None => raise ConfigError::MissingKey(path)
        }
      _ => raise ConfigError::TypeMismatch(path, "Table", cur.kind.name())
    }
  }
  cur
}
