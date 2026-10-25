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
    ConfigError::IoError("文件 config.json：找不到").to_string(),
    "读取失败：文件 config.json：找不到",
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
/// 白盒测试用的 site：固定标签，忽略路径
struct TestSite {
  kind : SourceKind
  label : String
}

///|
impl OriginSite for TestSite with fn kind(self : TestSite) -> SourceKind {
  self.kind
}

///|
impl OriginSite for TestSite with fn describe(self : TestSite, _ : KeyPath) -> String {
  self.label
}

///|
fn test_site(kind : SourceKind, label : String) -> &OriginSite {
  TestSite::{ kind, label, } as &OriginSite
}

///|
/// 树里每个节点（含表节点、数组节点）的路径和来源标签
fn node_origins(
  value : Value,
  prefix : String,
  out : Array[(String, String)],
) -> Unit {
  match value.origin {
    Some(site) =>
      out.push((prefix, OriginSite::describe(site, KeyPath::root())))
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
    Some(test_site(SourceKind::File, "file:base")),
  )
  let over = attach_origin(
    Value::table({ "db": Value::table({ "port": Value::int(2L) }) }),
    Some(test_site(SourceKind::Env, "env:over")),
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
    Some(test_site(SourceKind::Cli, "cli:--set")),
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

///|
/// 节点自己带了来源就保留，只给没标的节点补
test "attach_origin keeps origins already on the tree" {
  let value = Value::table({
    "a": Value::int(1L).with_origin(test_site(SourceKind::Env, "env:A")),
    "b": Value::int(2L),
  })
  let nodes = []
  node_origins(
    attach_origin(value, Some(test_site(SourceKind::Env, "env:APP"))),
    "",
    nodes,
  )
  let labels = nodes.map(fn(pair) { "\{pair.0}=\{pair.1}" })
  assert_true(labels.contains("a=env:A"))
  assert_true(labels.contains("b=env:APP"))
  assert_true(labels.contains("=env:APP"))
}

///|
/// 路径按段拼，点号只在展示时出现
test "KeyPath parses, extends and formats" {
  let path = KeyPath::parse("db.port")
  assert_eq(path.segments().to_owned(), ["db", "port"])
  assert_eq(path.to_string(), "db.port")
  let nested = path.add("user")
  assert_eq(nested.to_string(), "db.port.user")
  assert_eq(path.to_string(), "db.port")
  assert_true(KeyPath::root().is_empty())
  assert_false(KeyPath::parse("db").is_empty())
}
