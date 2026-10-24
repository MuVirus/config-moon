// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
/// 合并的三条规则：后覆盖前、表逐 key 合、数组整体换
test "merge rules" {
  let base = Value::table({
    "db": Value::table({
      "host": Value::str("localhost"),
      "port": Value::int(5432L),
    }),
    "hosts": Value::array([Value::str("a"), Value::str("b")]),
    "debug": Value::bool(false),
  })
  let over = Value::table({
    "db": Value::table({ "port": Value::int(6543L) }),
    "hosts": Value::array([Value::str("c")]),
  })
  assert_eq(
    merge(base, over),
    Value::table({
      "db": Value::table({
        "host": Value::str("localhost"),
        "port": Value::int(6543L),
      }),
      "hosts": Value::array([Value::str("c")]),
      "debug": Value::bool(false),
    }),
  )
}

///|
/// 后加的来源里出现新 key 也要留下
test "merge adds new keys" {
  let merged = merge(
    Value::table({ "a": Value::int(1L) }),
    Value::table({ "b": Value::int(2L) }),
  )
  assert_eq(merged, Value::table({ "a": Value::int(1L), "b": Value::int(2L) }))
}

///|
/// 表覆盖标量时是整张换掉，不报错
test "table replaces scalar" {
  let merged = merge(
    Value::table({ "a": Value::int(1L) }),
    Value::table({ "a": Value::str("now a string") }),
  )
  assert_eq(merged, Value::table({ "a": Value::str("now a string") }))
}

///|
/// 路径走不通时报 TypeMismatch，而不是静默变 Null
test "get_path on scalar reports TypeMismatch" {
  let value = Value::table({ "a": Value::int(1L) })
  let message = try {
    ignore(value.get_path("a.b"))
    "没有报错"
  } catch {
    ConfigError::TypeMismatch(path, expected, actual) =>
      "\{path} \{expected} \{actual}"
    e => e.to_string()
  }
  assert_eq(message, "a.b Table Int")
}

///|
/// 形状的名字直接进报错信息
test "kind name" {
  assert_eq(ValueKind::Null.name(), "Null")
  assert_eq(ValueKind::Bool(true).name(), "Bool")
  assert_eq(ValueKind::Int(1L).name(), "Int")
  assert_eq(ValueKind::Float(1.0).name(), "Float")
  assert_eq(ValueKind::Str("s").name(), "Str")
  assert_eq(ValueKind::Bytes(b"x").name(), "Bytes")
  assert_eq(ValueKind::Array([]).name(), "Array")
  assert_eq(ValueKind::Table(Map([])).name(), "Table")
}

///|
/// 报错的文字就是库的体验标准：键、期望、实际都要在
test "config error messages" {
  assert_eq(
    ConfigError::MissingKey("db.user").to_string(),
    "配置项 db.user 不存在：没有任何来源提供它",
  )
  assert_eq(
    ConfigError::TypeMismatch("db.host", "Int", "Str").to_string(),
    "配置项 db.host 类型不符：期望 Int，实际 Str",
  )
  assert_eq(
    ConfigError::ParseError("坏文本").to_string(),
    "解析失败：坏文本",
  )
  assert_eq(
    ConfigError::MergeConflict("db", "Table", "Str").to_string(),
    "配置项 db 合并冲突：Table 与 Str",
  )
}

///|
/// 没 `build()` 也能取值：现场合并
test "getters merge lazily" {
  let cfg = Config::new()
    .add(MemorySource::new(Value::table({ "a": Value::int(1L) })))
    .add(MemorySource::new(Value::table({ "a": Value::int(2L) })))
  assert_eq(cfg.get_int("a"), 2L)
}

///|
/// 树里每个节点（含表节点、数组节点）的路径和来源标签
fn node_origins(
  value : Value,
  prefix : String,
  out : Array[(String, String)],
) -> Unit {
  match value.origin {
    Some(origin) => out.push((prefix, origin.label))
    None => ()
  }
  match value.kind {
    ValueKind::Table(table) =>
      for key, child in table {
        let path = if prefix == "" { key } else { "\{prefix}.\{key}" }
        node_origins(child, path, out)
      }
    ValueKind::Array(items) =>
      for i, child in items {
        node_origins(child, "\{prefix}[\{i}]", out)
      }
    _ => ()
  }
}

///|
/// 表合表时，合并出的表节点记覆盖方的来源，没被覆盖的叶子仍记原来源
test "merge keeps the overriding table origin" {
  let base = attach_origin(
    Value::table({
      "db": Value::table({ "host": Value::str("localhost") }),
      "keep": Value::int(1L),
    }),
    Some(Origin::new(SourceKind::File, "file:base")),
  )
  let over = attach_origin(
    Value::table({ "db": Value::table({ "port": Value::int(2L) }) }),
    Some(Origin::new(SourceKind::Env, "env:over")),
  )
  let nodes = []
  node_origins(merge(base, over), "", nodes)
  let labels = nodes.map(fn(pair) { "\{pair.0}=\{pair.1}" })
  assert_true(labels.contains("=env:over"))
  assert_true(labels.contains("db=env:over"))
  assert_true(labels.contains("db.host=file:base"))
  assert_true(labels.contains("db.port=env:over"))
  assert_true(labels.contains("keep=file:base"))
}

///|
/// attach_origin 递归到底：表节点、数组节点、数组元素都带来源
test "attach_origin marks table and array nodes" {
  let value = attach_origin(
    Value::table({
      "db": Value::table({ "host": Value::str("localhost") }),
      "hosts": Value::array([Value::str("a"), Value::str("b")]),
    }),
    Some(Origin::new(SourceKind::Cli, "cli:--set")),
  )
  let nodes = []
  node_origins(value, "", nodes)
  assert_eq(nodes.length(), 6)
  for _, pair in nodes {
    assert_eq(pair.1, "cli:--set")
  }
}

///|
/// 没有来源就原样返回，不凭空造一层
test "attach_origin without origin leaves the tree alone" {
  let value = attach_origin(
    Value::table({ "a": Value::table({ "b": Value::int(1L) }) }),
    None,
  )
  let nodes = []
  node_origins(value, "", nodes)
  assert_eq(nodes.length(), 0)
}
