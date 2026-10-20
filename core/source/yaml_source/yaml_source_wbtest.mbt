// Whitebox tests for the yaml package: conversion and error edges live here.

///|
using @config {type ConfigError, type Value}

///|
using @yaml {type Yaml}

///|
/// 各种 Yaml 分支都能落到 Value
test "yaml variants convert to value kinds" {
  let v = parse_yaml(
    "i: 42\nf: 1.5\ns: hello\nb: true\nn: null\na: [1, 2]\nm: {k: v}\n",
  )
  assert_eq(
    v,
    Value::table({
      "i": Value::int(42L),
      "f": Value::float(1.5),
      "s": Value::str("hello"),
      "b": Value::bool(true),
      "n": Value::null(),
      "a": Value::array([Value::int(1L), Value::int(2L)]),
      "m": Value::table({ "k": Value::str("v") }),
    }),
  )
}

///|
/// 大整数按 Int64 原样保留
test "big integers survive" {
  let v = parse_yaml("id: 9007199254740993\n")
  assert_eq(v, Value::table({ "id": Value::int(9007199254740993L) }))
}

///|
/// 超出 Int64 的整数报错，不静默变成浮点
test "integer overflow reports ParseError" {
  let message = try {
    ignore(parse_yaml("id: 99999999999999999999\n"))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "整数 99999999999999999999 超出 Int64 范围")
}

///|
/// 浮点的几种写法，包括 YAML 的特殊值
test "float shapes" {
  let v = parse_yaml("a: 1.5\nb: -0.5\nc: 1.5e3\nd: .inf\n")
  assert_eq(
    v,
    Value::table({
      "a": Value::float(1.5),
      "b": Value::float(-0.5),
      "c": Value::float(1500.0),
      "d": Value::float(@double.infinity),
    }),
  )
}

///|
/// NaN 不能用相等比较，单独断言
test "nan" {
  let v = parse_yaml("e: .nan\n")
  match v.get_path("e").kind {
    @config.ValueKind::Float(f) => assert_true(f.is_nan())
    _ => assert_true(false)
  }
}

///|
/// YAML 认的布尔写法
test "boolean variants" {
  let v = parse_yaml(
    "a: true\nb: True\nc: TRUE\nd: false\ne: False\nf: FALSE\n",
  )
  assert_eq(
    v,
    Value::table({
      "a": Value::bool(true),
      "b": Value::bool(true),
      "c": Value::bool(true),
      "d": Value::bool(false),
      "e": Value::bool(false),
      "f": Value::bool(false),
    }),
  )
}

///|
/// `yes` / `no` 在 YAML 1.2 里是字符串
test "yes and no are strings" {
  let v = parse_yaml("a: yes\nb: no\n")
  assert_eq(v, Value::table({ "a": Value::str("yes"), "b": Value::str("no") }))
}

///|
/// `~` 和 `null` 都是 Null
test "null variants" {
  let v = parse_yaml("a: ~\nb: null\nc:\n")
  assert_eq(
    v,
    Value::table({ "a": Value::null(), "b": Value::null(), "c": Value::null() }),
  )
}

///|
/// 十六进制、八进制整数
test "hex and octal integers" {
  let v = parse_yaml("a: 0x2A\nb: 0o52\n")
  assert_eq(v, Value::table({ "a": Value::int(42L), "b": Value::int(42L) }))
}

///|
/// 时间戳这类没有标签的写法保持字符串
test "timestamp-like values stay strings" {
  let v = parse_yaml("when: 2026-10-20\n")
  assert_eq(v, Value::table({ "when": Value::str("2026-10-20") }))
}

///|
/// 引号包住的数字和布尔都不猜类型
test "quoted scalars stay strings" {
  let v = parse_yaml("a: \"42\"\nb: '1.5'\nc: \"true\"\n")
  assert_eq(
    v,
    Value::table({
      "a": Value::str("42"),
      "b": Value::str("1.5"),
      "c": Value::str("true"),
    }),
  )
}

///|
/// 块标量
test "block scalars" {
  let v = parse_yaml(
    "literal: |\n  line one\n  line two\nfolded: >\n  one\n  two\n",
  )
  assert_eq(
    v,
    Value::table({
      "literal": Value::str("line one\nline two\n"),
      "folded": Value::str("one two\n"),
    }),
  )
}

///|
/// 空文件、空文档、只有注释的文件和根节点为 `null` 的文件都是空表
test "empty documents are empty tables" {
  assert_eq(parse_yaml(""), Value::table({}))
  assert_eq(parse_yaml("# 只有注释\n"), Value::table({}))
  assert_eq(parse_yaml("---\n"), Value::table({}))
  assert_eq(parse_yaml("null\n"), Value::table({}))
}

///|
/// 重复键由库报错
test "duplicate keys report ParseError" {
  let message = try {
    ignore(parse_yaml("a: 1\na: 2\n"))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_true(message.contains("duplicated key"))
}

///|
/// 非字符串键由库报错
test "non-string keys report ParseError" {
  let message = try {
    ignore(parse_yaml("1: value\n"))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_true(message.contains("non-string"))
}

///|
/// 直接构造的 BadValue 报错，不悄悄变成 Null
test "bad value reports ParseError" {
  let message = try {
    ignore(yaml_to_value(Yaml::BadValue))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "YAML 里有无法表示的值")
}

///|
/// 嵌套的 BadValue 也会冒出来
test "nested bad value reports ParseError" {
  let message = try {
    ignore(yaml_to_value(Yaml::Map({ "a": Yaml::BadValue })))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "YAML 里有无法表示的值")
}

///|
/// 整数形状的判断
test "integer literal shapes" {
  assert_true(is_int_literal("0"))
  assert_true(is_int_literal("42"))
  assert_true(is_int_literal("-42"))
  assert_true(is_int_literal("+42"))
  assert_false(is_int_literal(""))
  assert_false(is_int_literal("-"))
  assert_false(is_int_literal("+"))
  assert_false(is_int_literal("1.0"))
  assert_false(is_int_literal("1e3"))
  assert_false(is_int_literal("42abc"))
}
