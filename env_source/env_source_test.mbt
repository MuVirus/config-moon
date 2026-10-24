// Blackbox tests for the environment source.

///|
using @config {type Config, type ConfigError, type SourceKind}

///|
using @env_source {type EnvSource}

///|
/// 每个测试用自己的前缀，互不干扰
fn set_vars(pairs : Array[(String, String)]) -> Unit {
  for pair in pairs {
    @env.set_env_var(pair.0, pair.1)
  }
}

///|
fn clear_vars(names : Array[String]) -> Unit {
  for name in names {
    @env.unset_env_var(name)
  }
}

///|
/// 前缀过滤、下划线变层级、字面量猜类型：四件事一起验
test "EnvSource reads prefixed variables as nested values" {
  set_vars([
    ("MOONFIG_ENV_DB_HOST", "localhost"),
    ("MOONFIG_ENV_DB_PORT", "6543"),
    ("MOONFIG_ENV_DEBUG", "true"),
    ("MOONFIG_ENV_RATIO", "0.5"),
    ("MOONFIG_ENV_EMPTY", ""),
    ("MOONFIG_OTHER", "ignored"),
  ])
  let cfg = Config::new().add(EnvSource::new("MOONFIG_ENV_")).build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 6543L)
  assert_true(cfg.get_bool("debug"))
  assert_eq(cfg.get_float("ratio"), 0.5)
  assert_eq(cfg.get_string("empty"), "")
  let message = try {
    ignore(cfg.get_string("other"))
    "没有报错"
  } catch {
    ConfigError::MissingKey(path) => path
    e => e.to_string()
  }
  assert_eq(message, "other")
  clear_vars([
    "MOONFIG_ENV_DB_HOST", "MOONFIG_ENV_DB_PORT", "MOONFIG_ENV_DEBUG", "MOONFIG_ENV_RATIO",
    "MOONFIG_ENV_EMPTY", "MOONFIG_OTHER",
  ])
}

///|
/// 点号也当层级；键名统一转小写
test "EnvSource splits on dots and lowercases names" {
  set_vars([("MOONFIG_DOT_LOG.LEVEL", "debug")])
  let cfg = Config::new().add(EnvSource::new("MOONFIG_DOT_")).build()
  assert_eq(cfg.get_string("log.level"), "debug")
  clear_vars(["MOONFIG_DOT_LOG.LEVEL"])
}

///|
/// 叶子来源指向具体变量，表节点只认前缀
test "EnvSource labels leaves with the variable name" {
  set_vars([
    ("MOONFIG_ORIGIN_DB_PORT", "6543"),
    ("MOONFIG_ORIGIN_DB_HOST", "localhost"),
  ])
  let cfg = Config::new().add(EnvSource::new("MOONFIG_ORIGIN_")).build()
  let port = cfg.origin_of("db.port").unwrap()
  assert_eq(port.kind, SourceKind::Env)
  assert_eq(port.label, "env:MOONFIG_ORIGIN_DB_PORT")
  let host = cfg.origin_of("db.host").unwrap()
  assert_eq(host.label, "env:MOONFIG_ORIGIN_DB_HOST")
  clear_vars(["MOONFIG_ORIGIN_DB_PORT", "MOONFIG_ORIGIN_DB_HOST"])
}

///|
/// 前缀外的变量一个都不读
test "EnvSource ignores variables outside the prefix" {
  set_vars([("MOONFIG_SCOPE_INSIDE", "1"), ("MOONFIG_OUTSIDE", "2")])
  let cfg = Config::new().add(EnvSource::new("MOONFIG_SCOPE_")).build()
  assert_eq(cfg.get_int("inside"), 1L)
  let message = try {
    ignore(cfg.get_string("outside"))
    "没有报错"
  } catch {
    ConfigError::MissingKey(path) => path
    e => e.to_string()
  }
  assert_eq(message, "outside")
  clear_vars(["MOONFIG_SCOPE_INSIDE", "MOONFIG_OUTSIDE"])
}

///|
/// `-1` 这种负数是整数，不是字符串
test "EnvSource reads negative integers" {
  set_vars([("MOONFIG_NEG_VALUE", "-7")])
  let cfg = Config::new().add(EnvSource::new("MOONFIG_NEG_")).build()
  assert_eq(cfg.get_int("value"), -7L)
  clear_vars(["MOONFIG_NEG_VALUE"])
}

///|
/// 标量占了层级名时报错，并点名两个变量
test "EnvSource reports a scalar shadowing a branch" {
  set_vars([("MOONFIG_CLASH_DB", "1"), ("MOONFIG_CLASH_DB_PORT", "2")])
  let message = try {
    ignore(Config::new().add(EnvSource::new("MOONFIG_CLASH_")).build())
    "没有报错"
  } catch {
    ConfigError::ParseError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains("MOONFIG_CLASH_DB_PORT"))
  assert_true(message.contains("db"))
  clear_vars(["MOONFIG_CLASH_DB", "MOONFIG_CLASH_DB_PORT"])
}

///|
/// 整数超出 `Int64` 时报错，消息里带变量名
test "EnvSource reports integer overflow with the variable name" {
  set_vars([("MOONFIG_OVERFLOW_VALUE", "99999999999999999999")])
  let message = try {
    ignore(Config::new().add(EnvSource::new("MOONFIG_OVERFLOW_")).build())
    "没有报错"
  } catch {
    ConfigError::ParseError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains("MOONFIG_OVERFLOW_VALUE"))
  assert_true(message.contains("Int64"))
  clear_vars(["MOONFIG_OVERFLOW_VALUE"])
}

///|
/// 前缀自己不是键；前缀后的名字有空层时也报错
test "EnvSource rejects malformed names" {
  set_vars([("MOONFIG_BAD_", "1")])
  let cfg = Config::new().add(EnvSource::new("MOONFIG_BAD_")).build()
  assert_eq(cfg.origins().length(), 0)
  clear_vars(["MOONFIG_BAD_"])

  set_vars([("MOONFIG_BAD2_A__B", "1")])
  let message = try {
    ignore(Config::new().add(EnvSource::new("MOONFIG_BAD2_")).build())
    "没有报错"
  } catch {
    ConfigError::ParseError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains("MOONFIG_BAD2_A__B"))
  clear_vars(["MOONFIG_BAD2_A__B"])
}
