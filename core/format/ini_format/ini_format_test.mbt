// Blackbox tests for the ini package, against its public API.

///|
using @config {
  type Config,
  type ConfigError,
  type MemorySource,
  type StringSource,
  type Value,
}

///|
using @ini_format {type IniFormat}

///|
/// 测试里省掉重复的 `StringSource::new(..., IniFormat::new())`
fn ini(text : String) -> StringSource {
  StringSource::new(text, IniFormat::new())
}

///|
/// 一篇正常的 INI：段落变层级，值猜类型
test "ini sections nest and values get typed" {
  let cfg = Config::new()
    .add(
      ini(
        "; 主库配置\n[db]\nhost = localhost\nport = 5432\n[db.pool]\nsize = 10\n[debug]\non = true\nratio = 0.5\n",
      ),
    )
    .build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 5432L)
  assert_eq(cfg.get_int("db.pool.size"), 10L)
  assert_true(cfg.get_bool("debug.on"))
  assert_eq(cfg.get_float("debug.ratio"), 0.5)
}

///|
/// 没有段落头的键落在根上
test "keys before any section land at the root" {
  let cfg = Config::new()
    .add(ini("name = service\n[db]\nport = 5432\n"))
    .build()
  assert_eq(cfg.get_string("name"), "service")
  assert_eq(cfg.get_int("db.port"), 5432L)
}

///|
/// INI 叠在内存来源上面，只覆盖同名键
test "ini over memory overrides only the same key" {
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
    .add(ini("[db]\nport = 6543\n"))
    .build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 6543L)
  assert_false(cfg.get_bool("debug"))
}

///|
/// 引号包住的值不猜类型
test "quoted values stay strings" {
  let cfg = Config::new()
    .add(ini("port = \"5432\"\nflag = 'true'\ncolor = #ff0000\n"))
    .build()
  assert_eq(cfg.get_string("port"), "5432")
  assert_eq(cfg.get_string("flag"), "true")
  assert_eq(cfg.get_string("color"), "#ff0000")
}

///|
/// 取值类型对不上时报 TypeMismatch，而不是给个默认值
test "wrong type reports TypeMismatch" {
  let cfg = Config::new().add(ini("[db]\nport = 5432\n")).build()
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
/// 缺段落时报 MissingKey
test "missing section reports MissingKey" {
  let cfg = Config::new().add(ini("[db]\nport = 5432\n")).build()
  let message = try {
    ignore(cfg.get_int("cache.port"))
    "没有报错"
  } catch {
    ConfigError::MissingKey(path) => path
    e => e.to_string()
  }
  assert_eq(message, "cache.port")
}
