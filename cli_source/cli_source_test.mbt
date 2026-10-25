// Blackbox tests for the command line source.

///|
using @config {type Config, type ConfigError, type SourceKind}

///|
using @cli_source {type CliSource}

///|
/// 参数表转配置
fn config_of(args : Array[String]) -> Config raise ConfigError {
  Config::new().add(CliSource::from_args(args)).build()
}

///|
/// `--key=value` 拆键和值，`-` 和 `.` 都变层级，值按字面猜类型
test "CliSource reads long options as nested values" {
  let cfg = config_of([
    "app", "--db.port=6543", "--log-level=debug", "--debug", "--no-color", "--ratio=0.5",
  ])
  assert_eq(cfg.get_int("db.port"), 6543L)
  assert_eq(cfg.get_string("log.level"), "debug")
  assert_true(cfg.get_bool("debug"))
  assert_false(cfg.get_bool("color"))
  assert_eq(cfg.get_float("ratio"), 0.5)
}

///|
/// 位置参数、短选项、`--` 之后的参数都不当配置
test "CliSource ignores non-config arguments" {
  let cfg = config_of(["app", "serve", "-v", "--port=1", "--", "--port=2"])
  assert_eq(cfg.get_int("port"), 1L)
  assert_eq(cfg.origins().length(), 1)
}

///|
/// 同一个键写两次，后写的赢
test "CliSource lets the later argument win" {
  let cfg = config_of(["--port=1", "--port=2"])
  assert_eq(cfg.get_int("port"), 2L)
}

///|
/// 空参数（`--=x`、`--a..b`）报 `ParseError`，不静默丢掉
test "CliSource rejects malformed keys" {
  let message = try {
    ignore(config_of(["--a..b=1"]))
    "没有报错"
  } catch {
    ConfigError::ParseError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains("--a..b"))
}

///|
/// 标量占了层级名时报错
test "CliSource reports a scalar shadowing a branch" {
  let message = try {
    ignore(config_of(["--a=1", "--a.b=2"]))
    "没有报错"
  } catch {
    ConfigError::ParseError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains("--a.b"))
  assert_true(message.contains("--a"))
}

///|
/// 来源标签不带值，密码不会漏进日志
test "CliSource labels leaves without their values" {
  let cfg = config_of(["--db-password=secret", "--db.port=6543"])
  let password = cfg.origin_of("db.password").unwrap()
  assert_eq(password.kind(), SourceKind::Cli)
  assert_eq(password.label(), "cli:--db-password")
  assert_eq(password.path().to_string(), "db.password")
  let port = cfg.origin_of("db.port").unwrap()
  assert_eq(port.label(), "cli:--db.port")
}

///|
/// 整数超出 `Int64` 时报错，消息里带参数名
test "CliSource reports integer overflow with the argument name" {
  let message = try {
    ignore(config_of(["--big=99999999999999999999"]))
    "没有报错"
  } catch {
    ConfigError::ParseError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains("--big"))
  assert_true(message.contains("Int64"))
}

///|
/// 标量挡住层级名、或后来的标量要整个盖掉已有层级，都报错
test "CliSource rejects a scalar replacing a branch" {
  let message = try {
    ignore(config_of(["--a.b=1", "--a=2"]))
    "没有报错"
  } catch {
    ConfigError::ParseError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains("--a"))
}

///|
/// 末尾空参数直接跳过
test "CliSource skips an empty long option" {
  let cfg = config_of(["app", "--"])
  assert_eq(cfg.origins().length(), 0)
}
