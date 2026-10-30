// Whitebox tests for the toml package: conversion edges live here.

///|
using @config {type ConfigError, type Value}

///|
/// 各种 TomlValue 分支都能落到 Value
test "toml variants convert to value kinds" {
  let v = parse_toml(
    "i = 42\nf = 1.5\ns = \"hello\"\nb = true\na = [1, 2]\nm = { k = \"v\" }\n",
  )
  assert_eq(
    v,
    Value::table({
      "i": Value::int(42L),
      "f": Value::float(1.5),
      "s": Value::str("hello"),
      "b": Value::bool(true),
      "a": Value::array([Value::int(1L), Value::int(2L)]),
      "m": Value::table({ "k": Value::str("v") }),
    }),
  )
}

///|
/// 大integer按 Int64 原样保留
test "big integers survive" {
  let v = parse_toml("id = 9007199254740993\n")
  assert_eq(v, Value::table({ "id": Value::int(9007199254740993L) }))
}

///|
/// 浮点的几种写法，包括 TOML 的特殊值
test "float shapes" {
  let v = parse_toml("a = 1.5\nb = -0.5\nc = 1.5e3\nd = inf\ne = -inf\n")
  assert_eq(
    v,
    Value::table({
      "a": Value::float(1.5),
      "b": Value::float(-0.5),
      "c": Value::float(1500.0),
      "d": Value::float(@double.infinity),
      "e": Value::float(@double.neg_infinity),
    }),
  )
}

///|
/// NaN 不能用相等比较，单独断言
test "nan" {
  let v = parse_toml("a = nan\n")
  match v.get_path("a").kind {
    @config.ValueKind::Float(f) => assert_true(f.is_nan())
    _ => assert_true(false)
  }
}

///|
/// 多行字符串
test "multiline strings" {
  let v = parse_toml(
    "literal = '''\nline one\nline two\n'''\nbasic = \"\"\"\nline one\nline two\n\"\"\"\n",
  )
  assert_eq(
    v,
    Value::table({
      "literal": Value::str("line one\nline two\n"),
      "basic": Value::str("line one\nline two\n"),
    }),
  )
}

///|
/// 转义序列
test "escape sequences" {
  let v = parse_toml(
    "a = \"line\\nnext\"\nb = \"tab\\there\"\nc = \"quote\\\"inside\"\nd = \"back\\\\slash\"\n",
  )
  assert_eq(
    v,
    Value::table({
      "a": Value::str("line\nnext"),
      "b": Value::str("tab\there"),
      "c": Value::str("quote\"inside"),
      "d": Value::str("back\\slash"),
    }),
  )
}

///|
/// 带引号的键
test "quoted keys" {
  let v = parse_toml("\"caf\u{e9}\" = \"coffee\"\n\"a.b\" = 1\n")
  assert_eq(
    v,
    Value::table({ "caf\u{e9}": Value::str("coffee"), "a.b": Value::int(1L) }),
  )
}

///|
/// 嵌套的段落array
test "nested arrays of tables" {
  let v = parse_toml(
    "[[server.replicas]]\nname = \"primary\"\n\n[[server.replicas]]\nname = \"secondary\"\n",
  )
  assert_eq(
    v,
    Value::table({
      "server": Value::table({
        "replicas": Value::array([
          Value::table({ "name": Value::str("primary") }),
          Value::table({ "name": Value::str("secondary") }),
        ]),
      }),
    }),
  )
}

///|
/// 空文件是空表
test "empty toml is an empty table" {
  assert_eq(parse_toml(""), Value::table({}))
  assert_eq(parse_toml("# 只有注释\n"), Value::table({}))
}

///|
/// 重复键由库报错
test "duplicate keys report ParseError" {
  let message = try {
    ignore(parse_toml("a = 1\na = 2\n"))
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_true(message.length() > 0)
}

///|
/// 根节点不是表时报错
test "non-table root reports ParseError" {
  let message = try {
    ignore(toml_root_to_value(@toml.TomlValue::TomlString("x")))
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "TOML root must be a table, got string")
}

///|
/// 日期时间取原文，不带类型名
test "datetime text" {
  assert_eq(
    datetime_text(@toml.TomlDateTime::OffsetDateTime("1979-05-27T07:32:00Z")),
    "1979-05-27T07:32:00Z",
  )
  assert_eq(
    datetime_text(@toml.TomlDateTime::LocalDateTime("1979-05-27T07:32:00")),
    "1979-05-27T07:32:00",
  )
  assert_eq(
    datetime_text(@toml.TomlDateTime::LocalDate("1979-05-27")),
    "1979-05-27",
  )
  assert_eq(
    datetime_text(@toml.TomlDateTime::LocalTime("07:32:00")),
    "07:32:00",
  )
}
