// Blackbox tests for validation.

///|
using @config {type KeyPath, type Rule}

///|
/// 故意写坏的配置：端口越界、用户名为空、日志级别拼错、`db` 下多了 `extra`
fn bad_config() -> Config raise {
  Config::new()
  .add(
    MemorySource::new(
      Value::table({
        "db": Value::table({
          "host": Value::str("localhost"),
          "port": Value::int(70000L),
          "user": Value::str(""),
          "extra": Value::bool(true),
        }),
        "log": Value::table({ "level": Value::str("verbose") }),
      }),
    ),
  )
  .build()
}

///|
fn bad_rules() -> Array[Rule] {
  [
    Rule::int_range("db.port", 1L, 65535L),
    Rule::string_len("db.user", 1, 64),
    Rule::one_of("log.level", ["debug", "info", "warn", "error"]),
    Rule::allowed_keys("db", ["host", "port", "user"]),
  ]
}

///|
/// 全部符合时安静通过
test "validate passes on a good config" {
  let cfg = Config::new()
    .add(
      MemorySource::new(
        Value::table({
          "db": Value::table({
            "host": Value::str("localhost"),
            "port": Value::int(5432L),
            "user": Value::str("admin"),
          }),
          "log": Value::table({ "level": Value::str("info") }),
        }),
      ),
    )
    .build()
  cfg.validate([
    Rule::int_range("db.port", 1L, 65535L),
    Rule::string_len("db.user", 1, 64),
    Rule::one_of("log.level", ["debug", "info", "warn", "error"]),
    Rule::allowed_keys("db", ["host", "port", "user"]),
  ])
}

///|
/// `validate` 遇到第一个错误就停，消息带路径、约束和实际值
test "validate stops at the first error" {
  let message = try {
    bad_config().validate(bad_rules())
    "no error"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    message, "invalid value for key 'db.port': expected 1..65535, got 70000",
  )
}

///|
/// `validate_all` 一次列全，顺序和规则表一致
test "validate_all lists every problem" {
  let errors = bad_config().validate_all(bad_rules())
  let messages = errors.map(fn(error) { error.to_string() })
  assert_eq(messages.length(), 4)
  assert_eq(
    messages[0],
    "invalid value for key 'db.port': expected 1..65535, got 70000",
  )
  assert_eq(
    messages[1],
    "invalid value for key 'db.user': expected 1..64 characters, got 0 characters",
  )
  assert_eq(
    messages[2],
    "invalid value for key 'log.level': expected debug / info / warn / error, got verbose",
  )
  assert_eq(messages[3], "key 'db.extra' is not allowed")
}

///|
/// 路径不存在时由规则报 `MissingKey`，不用另写必填规则
test "missing key is reported" {
  let cfg = Config::new()
    .add(MemorySource::new(Value::table({ "db": Value::table({}) })))
    .build()
  let message = try {
    cfg.validate([Rule::int_range("db.port", 1L, 65535L)])
    "no error"
  } catch {
    error => error.to_string()
  }
  assert_eq(message, "missing key 'db.port': no source provides it")
}

///|
/// 类型不符时，实际一栏写形状名，不写具体值
test "type mismatch is reported as InvalidValue" {
  let cfg = Config::new()
    .add(
      MemorySource::new(
        Value::table({ "db": Value::table({ "port": Value::str("5432") }) }),
      ),
    )
    .build()
  let message = try {
    cfg.validate([Rule::int_range("db.port", 1L, 65535L)])
    "no error"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    message, "invalid value for key 'db.port': expected 1..65535, got Str",
  )
}

///|
/// `allowed_keys` 只允许列出的键，未知键的路径指到具体的键
test "allowed_keys points at the extra key" {
  let cfg = Config::new()
    .add(
      MemorySource::new(
        Value::table({
          "db": Value::table({
            "host": Value::str("a"),
            "secret": Value::str("x"),
          }),
        }),
      ),
    )
    .build()
  let message = try {
    cfg.validate([Rule::allowed_keys("db", ["host"])])
    "no error"
  } catch {
    error => error.to_string()
  }
  assert_eq(message, "key 'db.secret' is not allowed")
}

///|
/// 自定义规则：返回 `None` 通过，`Some(实际值)` 失败
test "custom rule decides by itself" {
  let rule = Rule::custom("db.host", "non-empty", fn(value) {
    match value.kind {
      ValueKind::Str(text) =>
        if text.length() == 0 {
          Some("empty string")
        } else {
          None
        }
      kind => Some(kind.name())
    }
  })
  let good = Config::new()
    .add(
      MemorySource::new(
        Value::table({ "db": Value::table({ "host": Value::str("a") }) }),
      ),
    )
    .build()
  good.validate([rule])
  let bad = Config::new()
    .add(
      MemorySource::new(
        Value::table({ "db": Value::table({ "host": Value::str("") }) }),
      ),
    )
    .build()
  let message = try {
    bad.validate([rule])
    "no error"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    message, "invalid value for key 'db.host': expected non-empty, got empty string",
  )
}

///|
/// 给 `Validate` 实现用的两个检查函数
test "check helpers raise InvalidValue" {
  let range = try {
    @config.check_int_range(KeyPath::parse("db.port"), 70000L, 1L, 65535L)
    "no error"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    range, "invalid value for key 'db.port': expected 1..65535, got 70000",
  )
  let length = try {
    @config.check_string_len(KeyPath::parse("db.user"), "", 1, 64)
    "no error"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    length, "invalid value for key 'db.user': expected 1..64 characters, got 0 characters",
  )
  @config.check_int_range(KeyPath::parse("db.port"), 5432L, 1L, 65535L)
  @config.check_string_len(KeyPath::parse("db.user"), "admin", 1, 64)
}
