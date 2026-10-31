// Blackbox tests for the command line source.

///|
using @config {type Config, type ConfigError, type SourceKind}

///|
using @cli_source {type CliSource, type CliValueStyle}

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
/// 位置参数、没登记的短选项、`--` 之后的参数都不当配置
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
    "no error"
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
    "no error"
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
/// integer超出 `Int64` 时报错，消息里带参数名
test "CliSource reports integer overflow with the argument name" {
  let message = try {
    ignore(config_of(["--big=99999999999999999999"]))
    "no error"
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
    "no error"
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

///|
/// 默认的 `Equals` 风格不猜 `--key value`：裸 `--key` 还是布尔开关
test "CliSource keeps the equals style strict" {
  let cfg = config_of(["--debug", "serve"])
  assert_true(cfg.get_bool("debug"))
  assert_eq(cfg.origins().length(), 1)
}

///|
/// `Separate` 风格用下一个参数当值，后面的选项和 `--` 不会被吃掉
test "CliSource reads separate values in the separate style" {
  let cfg = Config::new()
    .add(
      CliSource::from_args([
        "--db.port", "6543", "--log-level", "debug", "--debug", "--no-color",
      ]).with_value_style(CliValueStyle::Separate),
    )
    .build()
  assert_eq(cfg.get_int("db.port"), 6543L)
  assert_eq(cfg.get_string("log.level"), "debug")
  assert_true(cfg.get_bool("debug"))
  assert_false(cfg.get_bool("color"))
}

///|
/// `Separate` 风格遇到 `--key=value` 直接报错，不悄悄换风格；消息里不带值
test "CliSource reports equals values in the separate style" {
  let message = try {
    ignore(
      Config::new()
      .add(
        CliSource::from_args(["--db.password=secret"]).with_value_style(
          CliValueStyle::Separate,
        ),
      )
      .build(),
    )
    "no error"
  } catch {
    ConfigError::ParseError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains("--db.password"))
  assert_true(message.contains("Separate"))
  assert_false(message.contains("secret"))
}

///|
/// `Separate` 风格下，`--` 和紧跟的选项都终止取值
test "CliSource stops separate values at the terminator and at options" {
  let cfg = Config::new()
    .add(
      CliSource::from_args(["--verbose", "--debug", "--", "serve"]).with_value_style(
        CliValueStyle::Separate,
      ),
    )
    .build()
  assert_true(cfg.get_bool("verbose"))
  assert_true(cfg.get_bool("debug"))
  assert_eq(cfg.origins().length(), 2)
}

///|
/// 登记过的短选项按当前风格取值：`Equals` 用 `=`，`Separate` 用下一个参数
test "CliSource reads short options in the selected style" {
  let equals = Config::new()
    .add(
      CliSource::from_args(["-p=1", "-p=2"]).with_short_option("p", "db.port"),
    )
    .build()
  assert_eq(equals.get_int("db.port"), 2L)
  let separate = Config::new()
    .add(
      CliSource::from_args(["-p", "1", "-p", "2"])
      .with_short_option("p", "db.port")
      .with_value_style(CliValueStyle::Separate),
    )
    .build()
  assert_eq(separate.get_int("db.port"), 2L)
}

///|
/// 短选项名字可以带前导 `-`；数组 key 的 `-` 和 `.` 都按层级处理
test "CliSource accepts dashed short names and normalizes array keys" {
  let cfg = Config::new()
    .add(
      CliSource::from_args(["-p=5432", "--log-level=a", "--log-level=b"])
      .with_short_option("-p", "db.port")
      .with_array("log-level"),
    )
    .build()
  assert_eq(cfg.get_int("db.port"), 5432L)
  assert_true(
    cfg.get_value("log.level").kind is @config.ValueKind::Array(items) &&
    items.length() == 2,
  )
}

///|
/// 短选项不许混用另一种风格
test "CliSource rejects the other style for short options" {
  let message = try {
    ignore(
      Config::new()
      .add(CliSource::from_args(["-p", "1"]).with_short_option("p", "db.port"))
      .build(),
    )
    "no error"
  } catch {
    ConfigError::ParseError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains("-p"))
  assert_true(message.contains("Equals"))
}

///|
/// 布尔短选项可以连写，false 用长选项的 `--no-` 写
test "CliSource reads clustered short flags" {
  let cfg = Config::new()
    .add(
      CliSource::from_args(["-vq", "--no-verbose"])
      .with_short_flag("v", "verbose")
      .with_short_flag("q", "quiet"),
    )
    .build()
  assert_false(cfg.get_bool("verbose"))
  assert_true(cfg.get_bool("quiet"))
}

///|
/// 布尔短选项不接受值，别让人以为 `-v=false` 生效了
test "CliSource rejects a value on a short flag" {
  let message = try {
    ignore(
      Config::new()
      .add(CliSource::from_args(["-v=false"]).with_short_flag("v", "verbose"))
      .build(),
    )
    "no error"
  } catch {
    ConfigError::ParseError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains("-v"))
  assert_true(message.contains("flag"))
}

///|
/// 没登记的短选项仍然忽略，跟以前一样
test "CliSource ignores unregistered short options" {
  let cfg = Config::new()
    .add(
      CliSource::from_args(["-x", "1", "-p=2"]).with_short_option(
        "p", "db.port",
      ),
    )
    .build()
  assert_eq(cfg.get_int("db.port"), 2L)
  assert_eq(cfg.origins().length(), 1)
}

///|
/// 值型短选项缺值时点名报错，不静默记成 true
test "CliSource reports a short option without a value" {
  let message = try {
    ignore(
      Config::new()
      .add(
        CliSource::from_args(["-p"])
        .with_short_option("p", "db.port")
        .with_value_style(CliValueStyle::Separate),
      )
      .build(),
    )
    "no error"
  } catch {
    ConfigError::ParseError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains("-p"))
  assert_true(message.contains("value"))
}

///|
/// 子命令和文件路径留在 argv 里，只有选项进入配置
test "CliSource keeps positionals out of the config" {
  let cfg = Config::new()
    .add(
      CliSource::from_args([
        "moonfmi", "simulate", "model.fmu", "--start", "0", "--stop", "10", "--step",
        "0.01",
      ]).with_value_style(CliValueStyle::Separate),
    )
    .build()
  assert_eq(cfg.get_int("start"), 0L)
  assert_eq(cfg.get_int("stop"), 10L)
  assert_eq(cfg.get_float("step"), 0.01)
  assert_eq(cfg.origins().length(), 3)
}

///|
/// 声明过的位置参数按非选项顺序映射，选项的值不占位置
test "CliSource maps declared positionals to keys" {
  let cfg = Config::new()
    .add(
      CliSource::from_args(
        [
          "moonfmi", "simulate", "model.fmu", "--start", "0", "--stop", "10", "--step",
          "0.01",
        ],
        program_name=true,
      )
      .with_positional(0, "command")
      .with_positional(1, "model")
      .with_value_style(CliValueStyle::Separate),
    )
    .build()
  assert_eq(cfg.get_string("command"), "simulate")
  assert_eq(cfg.get_string("model"), "model.fmu")
  assert_eq(cfg.get_int("start"), 0L)
  assert_eq(cfg.get_int("stop"), 10L)
  assert_eq(cfg.get_float("step"), 0.01)
  assert_eq(cfg.origins().length(), 5)
}

///|
/// 选项出现在位置参数前面时，选项吃掉的值得跳过
test "CliSource skips option values when counting positionals" {
  let cfg = Config::new()
    .add(
      CliSource::from_args(["--start", "5", "simulate", "model.fmu"])
      .with_value_style(CliValueStyle::Separate)
      .with_positional(0, "command")
      .with_positional(1, "model"),
    )
    .build()
  assert_eq(cfg.get_int("start"), 5L)
  assert_eq(cfg.get_string("command"), "simulate")
  assert_eq(cfg.get_string("model"), "model.fmu")
}

///|
/// `--` 之后即使像选项，也按位置参数算
test "CliSource counts everything after the terminator as positionals" {
  let cfg = Config::new()
    .add(
      CliSource::from_args(["--", "--start", "0"])
      .with_positional(0, "first")
      .with_positional(1, "second"),
    )
    .build()
  assert_eq(cfg.get_string("first"), "--start")
  assert_eq(cfg.get_int("second"), 0L)
}

///|
/// from_args 默认不跳过第 0 个；program_name=true 才把它当程序名
test "CliSource only skips the program name when told" {
  let with_name = Config::new()
    .add(CliSource::from_args(["app", "serve"]).with_positional(0, "first"))
    .build()
  assert_eq(with_name.get_string("first"), "app")
  let skipped = Config::new()
    .add(
      CliSource::from_args(["app", "serve"], program_name=true).with_positional(
        0, "first",
      ),
    )
    .build()
  assert_eq(skipped.get_string("first"), "serve")
}

///|
/// 位置参数的来源标签用原始 argv 下标，不带值
test "CliSource labels positionals by argv index" {
  let cfg = Config::new()
    .add(
      CliSource::from_args(["app", "serve"], program_name=true).with_positional(
        0, "command",
      ),
    )
    .build()
  let origin = cfg.origin_of("command").unwrap()
  assert_eq(origin.kind(), SourceKind::Cli)
  assert_eq(origin.label(), "cli:argv[1]")
}

///|
/// 多个位置映射到同一个数组 key 时按顺序累加
test "CliSource appends repeated positional mappings to arrays" {
  let cfg = Config::new()
    .add(
      CliSource::from_args(["a", "b", "c"])
      .with_positional(0, "files")
      .with_positional(1, "files")
      .with_positional(2, "files")
      .with_array("files"),
    )
    .build()
  assert_true(
    cfg.get_value("files").kind is @config.ValueKind::Array(items) &&
    items.length() == 3,
  )
}

///|
/// 没声明的位置参数不报错，也不留下空 key
test "CliSource ignores undeclared positions" {
  let cfg = Config::new()
    .add(CliSource::from_args(["a", "b"]).with_positional(0, "first"))
    .build()
  assert_eq(cfg.origins().length(), 1)
  assert_eq(cfg.get_string("first"), "a")
}

///|
/// 短选项的来源标签同样不带值
test "CliSource labels short options without their values" {
  let cfg = Config::new()
    .add(CliSource::from_args(["-p=secret"]).with_short_option("p", "db.port"))
    .build()
  let origin = cfg.origin_of("db.port").unwrap()
  assert_eq(origin.kind(), SourceKind::Cli)
  assert_eq(origin.label(), "cli:-p")
}

///|
/// `with_array` 声明的路径，写几次就按顺序收成数组
test "CliSource collects repeated keys into arrays" {
  let cfg = Config::new()
    .add(
      CliSource::from_args(["--tag=a", "--tag=b", "--tag=c"]).with_array("tag"),
    )
    .build()
  match cfg.get_value("tag").kind {
    @config.ValueKind::Array(items) => {
      assert_eq(items.length(), 3)
      assert_eq(items[0], @config.Value::str("a"))
      assert_eq(items[1], @config.Value::str("b"))
      assert_eq(items[2], @config.Value::str("c"))
    }
    _ => assert_true(false)
  }
}

///|
/// 只写一次也得到单元素数组，不会一会儿是标量、一会儿是数组
test "CliSource gives a declared array a single element" {
  let cfg = Config::new()
    .add(CliSource::from_args(["--tag=a"]).with_array("tag"))
    .build()
  assert_true(
    cfg.get_value("tag").kind is @config.ValueKind::Array(items) &&
    items.length() == 1,
  )
}

///|
/// 短选项和长选项共用同一个数组声明
test "CliSource collects repeated short options into arrays" {
  let cfg = Config::new()
    .add(
      CliSource::from_args(["-t", "a", "-t", "b"])
      .with_short_option("t", "tag")
      .with_array("tag")
      .with_value_style(CliValueStyle::Separate),
    )
    .build()
  assert_true(
    cfg.get_value("tag").kind is @config.ValueKind::Array(items) &&
    items.length() == 2,
  )
}

///|
/// 数组声明和层级撞车时报错，不静默覆盖
test "CliSource reports an array used as a branch" {
  let message = try {
    ignore(
      Config::new()
      .add(CliSource::from_args(["--db.port=1"]).with_array("db"))
      .build(),
    )
    "no error"
  } catch {
    ConfigError::ParseError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains("db"))
  assert_true(message.contains("array"))
}
