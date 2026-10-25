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
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    message, "配置项 db.port 不符合约束：期望 1..65535，实际 70000",
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
    "配置项 db.port 不符合约束：期望 1..65535，实际 70000",
  )
  assert_eq(
    messages[1],
    "配置项 db.user 不符合约束：期望 1..64 个字符，实际 0 个字符",
  )
  assert_eq(
    messages[2],
    "配置项 log.level 不符合约束：期望 debug / info / warn / error，实际 verbose",
  )
  assert_eq(messages[3], "配置项 db.extra 不在允许的键里")
}

///|
/// 路径不存在时由规则报 `MissingKey`，不用另写必填规则
test "missing key is reported" {
  let cfg = Config::new()
    .add(MemorySource::new(Value::table({ "db": Value::table({}) })))
    .build()
  let message = try {
    cfg.validate([Rule::int_range("db.port", 1L, 65535L)])
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    message, "配置项 db.port 不存在：没有任何来源提供它",
  )
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
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    message, "配置项 db.port 不符合约束：期望 1..65535，实际 Str",
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
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(message, "配置项 db.secret 不在允许的键里")
}

///|
/// 自定义规则：返回 `None` 通过，`Some(实际值)` 失败
test "custom rule decides by itself" {
  let rule = Rule::custom("db.host", "非空", fn(value) {
    match value.kind {
      ValueKind::Str(text) =>
        if text.length() == 0 {
          Some("空字符串")
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
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    message, "配置项 db.host 不符合约束：期望 非空，实际 空字符串",
  )
}

///|
/// 给 `Validate` 实现用的两个检查函数
test "check helpers raise InvalidValue" {
  let range = try {
    @config.check_int_range(KeyPath::parse("db.port"), 70000L, 1L, 65535L)
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    range, "配置项 db.port 不符合约束：期望 1..65535，实际 70000",
  )
  let length = try {
    @config.check_string_len(KeyPath::parse("db.user"), "", 1, 64)
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    length, "配置项 db.user 不符合约束：期望 1..64 个字符，实际 0 个字符",
  )
  @config.check_int_range(KeyPath::parse("db.port"), 5432L, 1L, 65535L)
  @config.check_string_len(KeyPath::parse("db.user"), "admin", 1, 64)
}
