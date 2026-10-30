// Blackbox tests for the toml package, against its public API.

///|
using @config {
  type StringSource,
  type Config,
  type ConfigError,
  type MemorySource,
  type Value,
}

///|
using @toml_format {type TomlFormat}

///|
/// 测试里省掉重复的 `StringSource::new(..., TomlFormat::new())`
fn toml(text : String) -> StringSource {
  StringSource::new(text, TomlFormat::new())
}

///|
/// 段落、点号键和各种标量
test "toml reads tables, dotted keys and scalars" {
  let cfg = Config::new()
    .add(
      toml(
        "title = \"app\"\nport = 5432\nratio = 0.5\ndebug = true\n\n[db]\nhost = \"localhost\"\n\n[db.pool]\nsize = 10\n",
      ),
    )
    .build()
  assert_eq(cfg.get_string("title"), "app")
  assert_eq(cfg.get_int("port"), 5432L)
  assert_eq(cfg.get_float("ratio"), 0.5)
  assert_true(cfg.get_bool("debug"))
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.pool.size"), 10L)
}

///|
/// 行内表和array
test "toml reads inline tables and arrays" {
  let cfg = Config::new()
    .add(
      toml(
        "db = { host = \"localhost\", port = 5432 }\nnumbers = [1, 2, 3]\nnames = [\"a\", \"b\"]\n",
      ),
    )
    .build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 5432L)
  assert_eq(
    cfg.get_value("numbers"),
    Value::array([Value::int(1L), Value::int(2L), Value::int(3L)]),
  )
  assert_eq(
    cfg.get_value("names"),
    Value::array([Value::str("a"), Value::str("b")]),
  )
}

///|
/// 点号键自己造层级
test "dotted keys nest" {
  let cfg = Config::new().add(toml("a.b.c = 1\n")).build()
  assert_eq(cfg.get_int("a.b.c"), 1L)
}

///|
/// 段落的array
test "arrays of tables" {
  let cfg = Config::new()
    .add(
      toml(
        "[[products]]\nname = \"Hammer\"\nsku = 1\n\n[[products]]\nname = \"Nail\"\nsku = 2\n",
      ),
    )
    .build()
  let products = cfg.get_value("products")
  assert_eq(
    products,
    Value::array([
      Value::table({ "name": Value::str("Hammer"), "sku": Value::int(1L) }),
      Value::table({ "name": Value::str("Nail"), "sku": Value::int(2L) }),
    ]),
  )
}

///|
/// 日期时间按原文当字符串
test "datetimes stay strings" {
  let cfg = Config::new()
    .add(
      toml(
        "created_at = 1979-05-27T07:32:00Z\nlocal = 1979-05-27T07:32:00\ndate = 1979-05-27\ntime = 07:32:00\n",
      ),
    )
    .build()
  assert_eq(cfg.get_string("created_at"), "1979-05-27T07:32:00Z")
  assert_eq(cfg.get_string("local"), "1979-05-27T07:32:00")
  assert_eq(cfg.get_string("date"), "1979-05-27")
  assert_eq(cfg.get_string("time"), "07:32:00")
}

///|
/// 注释和空行都能跳过
test "comments and blank lines" {
  let cfg = Config::new()
    .add(toml("# 主库\n\n[db]\nport = 5432 # 行尾注释\n"))
    .build()
  assert_eq(cfg.get_int("db.port"), 5432L)
}

///|
/// TOML 叠在内存来源上面，只覆盖同名键
test "toml over memory overrides only the same key" {
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
    .add(toml("[db]\nport = 6543\n"))
    .build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 6543L)
  assert_false(cfg.get_bool("debug"))
}

///|
/// 空文件得到空表
test "empty toml is an empty table" {
  let cfg = Config::new().add(toml("# 只有注释\n")).build()
  let message = try {
    ignore(cfg.get_string("db.host"))
    "no error"
  } catch {
    ConfigError::MissingKey(path) => path
    e => e.to_string()
  }
  assert_eq(message, "db.host")
}

///|
/// 取值类型对不上时报 TypeMismatch
test "wrong type reports TypeMismatch" {
  let cfg = Config::new().add(toml("[db]\nport = 5432\n")).build()
  let message = try {
    ignore(cfg.get_string("db.port"))
    "no error"
  } catch {
    ConfigError::TypeMismatch(path, expected, actual) =>
      "\{path} \{expected} \{actual}"
    e => e.to_string()
  }
  assert_eq(message, "db.port Str Int")
}

///|
/// 语法错误包成 ParseError
test "invalid toml reports ParseError" {
  let message = try {
    ignore(toml("a = [unclosed\n").collect())
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_true(message.length() > 0)
}

///|
/// array里混着不同类型报错
test "mixed array reports ParseError" {
  let message = try {
    ignore(toml("a = [1, \"two\", 3.0]\n").collect())
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "array elements must all have the same type")
}
