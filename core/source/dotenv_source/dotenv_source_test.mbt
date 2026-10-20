// Blackbox tests for the dotenv package, against its public API.

///|
using @config {type Config, type ConfigError, type MemorySource, type Value}

///|
using @dotenv_source {type DotenvSource}

///|
/// 正常的 `.env`：export 前缀、注释、平铺键、点号层级、值猜类型
test "dotenv reads keys, comments, exports and types" {
  let cfg = Config::new()
    .add(
      DotenvSource::from_str(
        "# 服务配置\n\nexport DB_HOST=localhost\nDB_PORT=5432\nDEBUG=false\nRATIO=0.5\ndb.pool.size=10\n",
      ),
    )
    .build()
  assert_eq(cfg.get_string("DB_HOST"), "localhost")
  assert_eq(cfg.get_int("DB_PORT"), 5432L)
  assert_false(cfg.get_bool("DEBUG"))
  assert_eq(cfg.get_float("RATIO"), 0.5)
  assert_eq(cfg.get_int("db.pool.size"), 10L)
}

///|
/// 下划线只是键名的一部分，不会自动变成层级
test "underscores do not become dots" {
  let cfg = Config::new()
    .add(DotenvSource::from_str("DB_HOST=localhost\n"))
    .build()
  assert_eq(cfg.get_string("DB_HOST"), "localhost")
  let message = try {
    ignore(cfg.get_string("DB.HOST"))
    "没有报错"
  } catch {
    ConfigError::MissingKey(path) => path
    e => e.to_string()
  }
  assert_eq(message, "DB.HOST")
}

///|
/// 引号包住的值不猜类型
test "quoted values stay strings" {
  let cfg = Config::new()
    .add(
      DotenvSource::from_str(
        "PORT=\"5432\"\nFLAG='true'\nCOLOR=#ff0000\nURL=https://example.com/#frag\n",
      ),
    )
    .build()
  assert_eq(cfg.get_string("PORT"), "5432")
  assert_eq(cfg.get_string("FLAG"), "true")
  assert_eq(cfg.get_string("COLOR"), "#ff0000")
  assert_eq(cfg.get_string("URL"), "https://example.com/#frag")
}

///|
/// dotenv 叠在内存来源上面，只覆盖同名键
test "dotenv over memory overrides only the same key" {
  let cfg = Config::new()
    .add(
      MemorySource::new(
        Value::table({
          "DB_HOST": Value::str("localhost"),
          "DB_PORT": Value::int(5432L),
          "debug": Value::bool(false),
        }),
      ),
    )
    .add(DotenvSource::from_str("DB_PORT=6543\n"))
    .build()
  assert_eq(cfg.get_string("DB_HOST"), "localhost")
  assert_eq(cfg.get_int("DB_PORT"), 6543L)
  assert_false(cfg.get_bool("debug"))
}

///|
/// 取值类型对不上时报 TypeMismatch，而不是给个默认值
test "wrong type reports TypeMismatch" {
  let cfg = Config::new().add(DotenvSource::from_str("DB_PORT=5432\n")).build()
  let message = try {
    ignore(cfg.get_string("DB_PORT"))
    "没有报错"
  } catch {
    ConfigError::TypeMismatch(path, expected, actual) =>
      "\{path} \{expected} \{actual}"
    e => e.to_string()
  }
  assert_eq(message, "DB_PORT Str Int")
}

///|
/// 缺键时报 MissingKey
test "missing key reports MissingKey" {
  let cfg = Config::new().add(DotenvSource::from_str("DB_PORT=5432\n")).build()
  let message = try {
    ignore(cfg.get_int("DB_HOST"))
    "没有报错"
  } catch {
    ConfigError::MissingKey(path) => path
    e => e.to_string()
  }
  assert_eq(message, "DB_HOST")
}
