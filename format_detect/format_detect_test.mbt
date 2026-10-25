// Blackbox tests for automatic format detection.

///|
using @config {
  type Config,
  type ConfigError,
  type MemorySource,
  type StringSource,
  type Value,
}

///|
using @format_detect {type Detector}

///|
fn detector() -> Detector raise ConfigError {
  Detector::new([@json_format.JsonFormat::new(), @toml_format.TomlFormat::new()])
}

///|
fn config_of(value : Value) -> Config raise ConfigError {
  Config::new().add(MemorySource::new(value)).build()
}

///|
/// 后缀认识时直接走后缀，不看内容
test "detector uses a known suffix first" {
  let cfg = Config::new()
    .add(StringSource::new("db = { port = 5432 }", detector()))
    .build()
  assert_eq(cfg.get_int("db.port"), 5432L)
}

///|
/// 后缀大小写不敏感
test "detector normalizes suffix case" {
  let bytes = @utf8.encode("{\"db\": {\"port\": 5432}}")
  let value = detector().decode_path("APP.JSON", bytes)
  assert_eq(config_of(value).get_int("db.port"), 5432L)
}

///|
/// 没有后缀时按内容猜
test "detector sniffs content when there is no suffix" {
  let bytes = @utf8.encode("{\"db\": {\"port\": 5432}}")
  let value = detector().decode_path("app", bytes)
  assert_eq(config_of(value).get_int("db.port"), 5432L)
}

///|
/// 后缀不认识时也按内容猜
test "detector sniffs content when the suffix is unknown" {
  let bytes = @utf8.encode("{\"db\": {\"port\": 5432}}")
  let value = detector().decode_path("app.conf", bytes)
  assert_eq(config_of(value).get_int("db.port"), 5432L)
}

///|
/// 后缀认识但内容写坏了：直接报错，不偷偷换解析器
test "detector does not fall back after a known suffix fails" {
  let bytes = @utf8.encode("db = { port = 5432 }")
  let error = try {
    ignore(detector().decode_path("app.json", bytes))
    None
  } catch {
    e => Some(e)
  }
  assert_true(error is Some(ConfigError::ParseError(_)))
}

///|
/// 后缀和内容都不认识：报 UnknownFormat，并列出候选后缀
test "detector reports UnknownFormat with supported suffixes" {
  let message = try {
    ignore(detector().decode_path("app.conf", @utf8.encode("plain text")))
    "没有报错"
  } catch {
    ConfigError::UnknownFormat(name, suffixes) => {
      assert_eq(name, "app.conf")
      assert_eq(suffixes, ["json", "toml"])
      "无法判断"
    }
    e => e.to_string()
  }
  assert_eq(message, "无法判断")
}

///|
/// 重复后缀在构造阶段报错，不让顺序决定赢家
test "detector rejects duplicate suffixes" {
  let error = try {
    ignore(
      Detector::new([
        @json_format.JsonFormat::new(),
        @json_format.JsonFormat::new(),
      ]),
    )
    None
  } catch {
    e => Some(e)
  }
  assert_true(error is Some(ConfigError::ParseError(_)))
}

///|
struct FirstFormat {}

///|
impl @config.Format for FirstFormat with fn decode(_ : FirstFormat, _ : Bytes) -> Value raise ConfigError {
  Value::table({ "winner": Value::str("first") })
}

///|
impl @config.Format for FirstFormat with fn sniff(_ : FirstFormat, _ : Bytes) -> Bool {
  true
}

///|
struct SecondFormat {}

///|
impl @config.Format for SecondFormat with fn decode(_ : SecondFormat, _ : Bytes) -> Value raise ConfigError {
  Value::table({ "winner": Value::str("second") })
}

///|
impl @config.Format for SecondFormat with fn sniff(_ : SecondFormat, _ : Bytes) -> Bool {
  true
}

///|
/// 候选顺序就是优先级
test "detector candidate order is the priority" {
  let first = Detector::new([FirstFormat::{ }, SecondFormat::{ }]).decode_path(
    "app",
    @utf8.encode("anything"),
  )
  let second = Detector::new([SecondFormat::{ }, FirstFormat::{ }]).decode_path(
    "app",
    @utf8.encode("anything"),
  )
  assert_eq(config_of(first).get_string("winner"), "first")
  assert_eq(config_of(second).get_string("winner"), "second")
}

///|
test "yaml format declares its suffixes" {
  let detector = Detector::new([@yaml_format.YamlFormat::new()])
  assert_eq(detector.supported_suffixes(), ["yaml", "yml"])
  let cfg = Config::new()
    .add(StringSource::new("db:\n  port: 5432\n", detector))
    .build()
  assert_eq(cfg.get_int("db.port"), 5432L)
}
