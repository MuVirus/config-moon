// Blackbox tests run against the package's public API.
// 这里只测核心自己：合并、取值、错误。
// 凡是和具体格式有关的（JSON）都去 `json/` 包测。

///|
using @config {
  type Config,
  type ConfigError,
  type MemorySource,
  type Value,
  type ValueKind,
}

///|
/// 用户侧最小的用法：两个 MemorySource 合起来取值
test "merge later source wins, tables merge per key" {
  let defaults = MemorySource::new(
    Value::table({
      "db": Value::table({
        "host": Value::str("localhost"),
        "port": Value::int(5432L),
      }),
      "debug": Value::bool(false),
    }),
  )
  let overrides = MemorySource::new(
    Value::table({ "db": Value::table({ "port": Value::int(6543L) }) }),
  )
  let cfg = Config::new().add(defaults).add(overrides).build()
  assert_eq(cfg.get_string("db.host"), "localhost") // 来自 defaults，没被覆盖
  assert_eq(cfg.get_int("db.port"), 6543L) // 来自 overrides，后加的赢
  assert_false(cfg.get_bool("debug")) // 只有 defaults 提供，保持 false
}

///|
/// 数组整体替换，不拼接
test "array is replaced, not concatenated" {
  let base = MemorySource::new(
    Value::table({ "hosts": Value::array([Value::str("a"), Value::str("b")]) }),
  )
  let over = MemorySource::new(
    Value::table({ "hosts": Value::array([Value::str("c")]) }),
  )
  let cfg = Config::new().add(base).add(over).build()
  assert_eq(cfg.get_value("hosts").kind, ValueKind::Array([Value::str("c")]))
}

///|
/// 缺 key 报 MissingKey，并把路径原样带出来
test "missing key raises MissingKey" {
  let cfg = Config::new()
    .add(
      MemorySource::new(
        Value::table({ "db": Value::table({ "host": Value::str("localhost") }) }),
      ),
    )
    .build()
  let message = try {
    ignore(cfg.get_string("db.user"))
    "没有报错"
  } catch {
    ConfigError::MissingKey(path) => "缺少 \{path}"
    e => e.to_string()
  }
  assert_eq(message, "缺少 db.user")
}

///|
/// 类型不对报 TypeMismatch：哪个键、期望什么、实际什么都要说清楚
test "wrong type raises TypeMismatch" {
  let cfg = Config::new()
    .add(
      MemorySource::new(
        Value::table({ "db": Value::table({ "host": Value::str("localhost") }) }),
      ),
    )
    .build()
  let message = try {
    ignore(cfg.get_int("db.host"))
    "没有报错"
  } catch {
    ConfigError::TypeMismatch(path, expected, actual) =>
      "\{path}: 期望 \{expected}，实际 \{actual}"
    e => e.to_string()
  }
  assert_eq(message, "db.host: 期望 Int，实际 Str")
}

///|
/// 每个取值函数都要说清楚自己期望什么
test "getters report expected and actual" {
  let cfg = Config::new()
    .add(
      MemorySource::new(
        Value::table({ "n": Value::int(1L), "s": Value::str("x") }),
      ),
    )
    .build()
  assert_eq(
    type_error_of("Str", () => ignore(cfg.get_string("n"))),
    "n: 期望 Str，实际 Int",
  )
  assert_eq(
    type_error_of("Int", () => ignore(cfg.get_int("s"))),
    "s: 期望 Int，实际 Str",
  )
  assert_eq(
    type_error_of("Bool", () => ignore(cfg.get_bool("s"))),
    "s: 期望 Bool，实际 Str",
  )
  assert_eq(
    type_error_of("Float", () => ignore(cfg.get_float("s"))),
    "s: 期望 Float，实际 Str",
  )
}

///|
/// 跑一段注定报错的代码，把 `TypeMismatch` 拼成一句话
fn type_error_of(expected : String, f : () -> Unit raise ConfigError) -> String {
  try {
    f()
    "没有报错"
  } catch {
    ConfigError::TypeMismatch(path, e, actual) =>
      if e == expected {
        "\{path}: 期望 \{e}，实际 \{actual}"
      } else {
        "报的不是 \{expected}，而是 \{e}"
      }
    e => e.to_string()
  }
}
