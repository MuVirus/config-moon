// Blackbox tests run against the package's public API.
// 这里只测核心自己：合并、取值、错误。
// 凡是和具体格式有关的（JSON）都去 `json/` 包测。

///|
using @config {
  type BytesSource,
  type Config,
  type ConfigError,
  type MemorySource,
  type MergeRule,
  type Origin,
  type SourceKind,
  type StringSource,
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
  assert_eq(
    type_error_of("Bytes", () => ignore(cfg.get_bytes("s"))),
    "s: 期望 Bytes，实际 Str",
  )
}

///|
/// 字节串原样取出来
test "get_bytes returns the raw bytes" {
  let cfg = Config::new()
    .add(
      MemorySource::new(Value::table({ "blob": Value::bytes(b"\x01\x02\xff") })),
    )
    .build()
  assert_eq(cfg.get_bytes("blob"), b"\x01\x02\xff")
}

///|
/// 测试用的格式：把字节原样当字符串，不做解析
struct EchoFormat {}

///|
impl @config.Format for EchoFormat with fn decode(_ : EchoFormat, bytes : Bytes) -> Value raise ConfigError {
  let text = @utf8.decode(bytes) catch {
    _ => raise ConfigError::ParseError("不是合法的 UTF-8")
  }
  Value::str(text)
}

///|
/// 文本先编码成字节，再交给格式
test "StringSource encodes text before decoding" {
  let source = StringSource::new("hello", EchoFormat::{ })
  assert_eq(@config.Source::collect(source), Value::str("hello"))
}

///|
/// 字节原样交给格式
test "BytesSource passes bytes through" {
  let source = BytesSource::new(b"hi", EchoFormat::{ })
  assert_eq(@config.Source::collect(source), Value::str("hi"))
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

///|
/// 测试用的来源：值、来源都自己给
struct KindedSource {
  value : Value
  origin : Origin
}

///|
pub impl @config.Source for KindedSource with fn collect(self : KindedSource) -> Value {
  self.value
}

///|
pub impl @config.Source for KindedSource with fn origin(self : KindedSource) -> Origin? {
  Some(self.origin)
}

///|
fn kinded(value : Value, kind : SourceKind, label : String) -> KindedSource {
  KindedSource::{ value, origin: Origin::new(kind, label), }
}

///|
/// 来源跟着赢家走：后加的来源覆盖了 db.port，来源就是后加的那层
test "origin_of follows the winning layer" {
  let cfg = Config::new()
    .add(
      MemorySource::new(
        Value::table({
          "db": Value::table({
            "host": Value::str("localhost"),
            "port": Value::int(5432L),
          }),
        }),
      ),
    )
    .add(
      MemorySource::new(
        Value::table({ "db": Value::table({ "port": Value::int(6543L) }) }),
      ),
    )
    .build()
  let origin = cfg.origin_of("db.port").unwrap()
  assert_eq(origin.kind, SourceKind::Memory)
  assert_eq(origin.label, "memory")
  assert_true(cfg.origin_of("db.user") is None)
}

///|
/// origins() 列出叶子路径，表节点不算叶子
test "origins lists every leaf" {
  let cfg = Config::new()
    .add(
      kinded(
        Value::table({
          "db": Value::table({ "host": Value::str("localhost") }),
          "debug": Value::bool(false),
        }),
        SourceKind::File,
        "file:config/app.json",
      ),
    )
    .build()
  let origins = cfg.origins()
  assert_eq(origins.length(), 2)
  let labels = origins.map(fn(pair) { "\{pair.0}=\{pair.1.label}" })
  assert_true(labels.contains("db.host=file:config/app.json"))
  assert_true(labels.contains("debug=file:config/app.json"))
}

///|
/// 来源不同不算值不同
test "value equality ignores origin" {
  let from_memory = Config::new()
    .add(MemorySource::new(Value::table({ "k": Value::str("x") })))
    .build()
    .get_value("k")
  let from_file = Config::new()
    .add(
      kinded(
        Value::table({ "k": Value::str("x") }),
        SourceKind::File,
        "file:config.json",
      ),
    )
    .build()
    .get_value("k")
  assert_eq(from_memory, from_file)
}

///|
/// FirstWins：先加的赢，后加只补空缺
test "FirstWins keeps the earlier value" {
  let cfg = Config::new()
    .add(MemorySource::new(Value::table({ "a": Value::int(1L) })))
    .add(MemorySource::new(Value::table({ "a": Value::int(2L) })))
    .with_rule(MergeRule::FirstWins)
    .build()
  assert_eq(cfg.get_int("a"), 1L)
}

///|
/// ByKind：数组里越靠前越优先，同一档内后加的赢
test "ByKind ranks sources by kind" {
  let env = kinded(
    Value::table({ "a": Value::int(3L) }),
    SourceKind::Env,
    "env:A",
  )
  let file = kinded(
    Value::table({ "a": Value::int(2L) }),
    SourceKind::File,
    "file:a",
  )
  let memory = kinded(
    Value::table({ "a": Value::int(1L) }),
    SourceKind::Memory,
    "memory",
  )
  let env_wins = Config::new()
    .add(memory)
    .add(file)
    .add(env)
    .with_rule(MergeRule::ByKind([SourceKind::Env, SourceKind::File]))
    .build()
  assert_eq(env_wins.get_int("a"), 3L)
  let memory_wins = Config::new()
    .add(memory)
    .add(file)
    .add(env)
    .with_rule(MergeRule::ByKind([SourceKind::Memory]))
    .build()
  assert_eq(memory_wins.get_int("a"), 1L)
}

///|
/// Custom：函数拿到的前一个是已经合好的部分
test "Custom rule decides the merge" {
  let cfg = Config::new()
    .add(MemorySource::new(Value::table({ "a": Value::int(1L) })))
    .add(MemorySource::new(Value::table({ "a": Value::int(2L) })))
    .with_rule(MergeRule::Custom(fn(base, _over) { base }))
    .build()
  assert_eq(cfg.get_int("a"), 1L)
}
