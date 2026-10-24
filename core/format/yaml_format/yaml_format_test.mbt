// Blackbox tests for the yaml package, against its public API.

///|
using @config {
  type StringSource,
  type Config,
  type ConfigError,
  type MemorySource,
  type Value,
}

///|
using @yaml_format {type YamlFormat}

///|
/// 测试里省掉重复的 `StringSource::new(..., YamlFormat::new())`
fn yaml(text : String) -> StringSource {
  StringSource::new(text, YamlFormat::new())
}

///|
/// 嵌套映射、序列和各种标量
test "yaml reads nested mappings, sequences and scalars" {
  let cfg = Config::new()
    .add(
      yaml(
        "db:\n  host: localhost\n  port: 5432\n  ratio: 0.5\n  enabled: true\n  nothing: null\nservers:\n  - one\n  - two\n",
      ),
    )
    .build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 5432L)
  assert_eq(cfg.get_float("db.ratio"), 0.5)
  assert_true(cfg.get_bool("db.enabled"))
  assert_eq(cfg.get_value("db.nothing"), Value::null())
  assert_eq(
    cfg.get_value("servers"),
    Value::array([Value::str("one"), Value::str("two")]),
  )
}

///|
/// 根节点是映射时，键可以按点号路径取
test "nested keys are reachable by dotted path" {
  let cfg = Config::new().add(yaml("a:\n  b:\n    c: 1\n")).build()
  assert_eq(cfg.get_int("a.b.c"), 1L)
}

///|
/// 引号包住的标量不猜类型
test "quoted scalars stay strings" {
  let cfg = Config::new()
    .add(yaml("port: \"5432\"\nflag: 'true'\nnothing: 'null'\n"))
    .build()
  assert_eq(cfg.get_string("port"), "5432")
  assert_eq(cfg.get_string("flag"), "true")
  assert_eq(cfg.get_string("nothing"), "null")
}

///|
/// 注释、文档头和空行都能跳过
test "comments and document marker" {
  let cfg = Config::new()
    .add(yaml("%YAML 1.2\n---\n# 主库\ndb:\n  port: 5432 # 行尾注释\n"))
    .build()
  assert_eq(cfg.get_int("db.port"), 5432L)
}

///|
/// 流式写法和块式写法等价
test "flow collections" {
  let cfg = Config::new()
    .add(yaml("db: { host: localhost, port: 5432 }\nservers: [one, two]\n"))
    .build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 5432L)
  assert_eq(
    cfg.get_value("servers"),
    Value::array([Value::str("one"), Value::str("two")]),
  )
}

///|
/// 锚点和别名
test "anchors and aliases" {
  let cfg = Config::new()
    .add(
      yaml(
        "defaults: &defaults\n  host: localhost\n  port: 5432\ndb: *defaults\n",
      ),
    )
    .build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 5432L)
}

///|
/// YAML 叠在内存来源上面，只覆盖同名键
test "yaml over memory overrides only the same key" {
  let cfg = Config::new()
    .add(
      MemorySource::new(
        Value::table({
          "db": Value::table({
            "host": Value::str("localhost"),
            "port": Value::int(5432L),
          }),
          "debug": Value::bool(false),
        }),
      ),
    )
    .add(yaml("db:\n  port: 6543\n"))
    .build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 6543L)
  assert_false(cfg.get_bool("debug"))
}

///|
/// 空文件得到空表，取值时报 MissingKey
test "empty yaml is an empty table" {
  let cfg = Config::new().add(yaml("# 只有注释\n")).build()
  let message = try {
    ignore(cfg.get_string("db.host"))
    "没有报错"
  } catch {
    ConfigError::MissingKey(path) => path
    e => e.to_string()
  }
  assert_eq(message, "db.host")
}

///|
/// 取值类型对不上时报 TypeMismatch
test "wrong type reports TypeMismatch" {
  let cfg = Config::new().add(yaml("db:\n  port: 5432\n")).build()
  let message = try {
    ignore(cfg.get_string("db.port"))
    "没有报错"
  } catch {
    ConfigError::TypeMismatch(path, expected, actual) =>
      "\{path} \{expected} \{actual}"
    e => e.to_string()
  }
  assert_eq(message, "db.port Str Int")
}

///|
/// 多个文档报错，不会悄悄只取第一段
test "multiple documents report ParseError" {
  let message = try {
    ignore(yaml("a: 1\n---\nb: 2\n").collect())
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "YAML 文本包含多个文档，只支持一个")
}

///|
/// 语法错误包成 ParseError
test "invalid yaml reports ParseError" {
  let message = try {
    ignore(yaml("a: [1, 2\n").collect())
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_true(message.length() > 0)
}
