// Whitebox tests for the xml package: conversion edges live here.

///|
using @config {type ConfigError, type Value}

///|
/// 各种形状都能落到 Value
test "xml shapes convert to value kinds" {
  let v = parse_xml(
    "<config><i>42</i><f>1.5</f><s>hello</s><b>true</b><e/><n>5432</n></config>",
  )
  assert_eq(
    v,
    Value::table({
      "i": Value::int(42L),
      "f": Value::float(1.5),
      "s": Value::str("hello"),
      "b": Value::bool(true),
      "e": Value::str(""),
      "n": Value::int(5432L),
    }),
  )
}

///|
/// 空白不算数
test "whitespace around text is ignored" {
  let v = parse_xml("<config><a>   hello   </a></config>")
  assert_eq(v, Value::table({ "a": Value::str("hello") }))
}

///|
/// 缩进留下的空白不是混排内容
test "indentation does not create mixed content" {
  let v = parse_xml("<config>\n  <a>1</a>\n  <b>2</b>\n</config>")
  assert_eq(v, Value::table({ "a": Value::int(1L), "b": Value::int(2L) }))
}

///|
/// 属性落在 `@` 开头的键上
test "attributes live under an @ prefix" {
  let v = parse_xml("<config><db host=\"localhost\" port=\"5432\"/></config>")
  assert_eq(
    v,
    Value::table({
      "db": Value::table({
        "@host": Value::str("localhost"),
        "@port": Value::int(5432L),
      }),
    }),
  )
}

///|
/// 命名空间声明不是配置项
test "namespace declarations are skipped" {
  let v = parse_xml(
    "<config xmlns=\"urn:d\" xmlns:x=\"urn:x\"><x:a>1</x:a></config>",
  )
  assert_eq(v, Value::table({ "x:a": Value::int(1L) }))
}

///|
/// 命名空间前缀保留在名字里
test "namespace prefixes stay in the name" {
  let v = parse_xml("<config xmlns:x=\"urn:x\"><x:a>1</x:a></config>")
  assert_eq(v, Value::table({ "x:a": Value::int(1L) }))
}

///|
/// 混合内容放在 `#text` 上
test "mixed content lands on #text" {
  let v = parse_xml("<config><a>text<b>x</b></a></config>")
  assert_eq(
    v,
    Value::table({
      "a": Value::table({ "b": Value::str("x"), "#text": Value::str("text") }),
    }),
  )
}

///|
/// 同名兄弟元素：一个时是那个值，多个时是数组
test "one sibling is a value, many are an array" {
  let v = parse_xml("<config><a><b>1</b></a><a><b>2</b><b>3</b></a></config>")
  assert_eq(
    v,
    Value::table({
      "a": Value::array([
        Value::table({ "b": Value::int(1L) }),
        Value::table({ "b": Value::array([Value::int(2L), Value::int(3L)]) }),
      ]),
    }),
  )
}

///|
/// 实体引用由解析器解好
test "entities are decoded" {
  let v = parse_xml("<config><a>Tom &amp; Jerry</a></config>")
  assert_eq(v, Value::table({ "a": Value::str("Tom & Jerry") }))
}

///|
/// CDATA 是字面文字，一定是字符串
test "cdata is always a string" {
  let v = parse_xml(
    "<config><a><![CDATA[1.0]]></a><b><![CDATA[true]]></b></config>",
  )
  assert_eq(
    v,
    Value::table({ "a": Value::str("1.0"), "b": Value::str("true") }),
  )
}

///|
/// CDATA 和普通文字混在一起时按普通文字处理
test "cdata mixed with plain text is not literal" {
  let v = parse_xml("<config><a>x<![CDATA[1.0]]></a></config>")
  assert_eq(v, Value::table({ "a": Value::str("x1.0") }))
}

///|
/// 大整数不丢
test "big integers survive" {
  let v = parse_xml("<config><id>9007199254740993</id></config>")
  assert_eq(v, Value::table({ "id": Value::int(9007199254740993L) }))
}

///|
/// 整数溢出 Int64 报错，不静默截断
test "integer overflow reports ParseError" {
  let message = try {
    ignore(parse_xml("<config><id>99999999999999999999</id></config>"))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "整数 99999999999999999999 超出 Int64 范围")
}

///|
/// 只有 `true` / `false` 是布尔
test "only true and false are booleans" {
  let v = parse_xml("<config><a>true</a><b>True</b><c>yes</c></config>")
  assert_eq(
    v,
    Value::table({
      "a": Value::bool(true),
      "b": Value::str("True"),
      "c": Value::str("yes"),
    }),
  )
}

///|
/// 像数字但不是数字的东西一律当字符串
test "number-ish strings stay strings" {
  let v = parse_xml(
    "<config><a>1.</a><b>.5</b><c>1.2.3</c><d>12abc</d></config>",
  )
  assert_eq(
    v,
    Value::table({
      "a": Value::str("1."),
      "b": Value::str(".5"),
      "c": Value::str("1.2.3"),
      "d": Value::str("12abc"),
    }),
  )
}

///|
/// 根元素自己的属性落在顶层
test "root attributes land at the top level" {
  let v = parse_xml("<config version=\"1\"><a>1</a></config>")
  assert_eq(
    v,
    Value::table({ "@version": Value::int(1L), "a": Value::int(1L) }),
  )
}

///|
/// 根元素总是壳，它自己的文字落在 `#text` 上
test "root text lands on #text" {
  let v = parse_xml("<config>hello</config>")
  assert_eq(v, Value::table({ "#text": Value::str("hello") }))
}

///|
/// 空文档得到空表
test "an empty document is an empty table" {
  assert_eq(parse_xml(""), Value::table({}))
  assert_eq(parse_xml("<!-- 只有注释 -->"), Value::table({}))
}

///|
/// 嵌套的表逐层摊开
test "nested tables nest" {
  let v = parse_xml("<config><a><b><c>1</c></b></a></config>")
  assert_eq(
    v,
    Value::table({
      "a": Value::table({ "b": Value::table({ "c": Value::int(1L) }) }),
    }),
  )
}

///|
/// 解析错误带上行号列号
test "parse errors carry a position" {
  let message = try {
    ignore(parse_xml("<config><a>1</config>"))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_true(message.contains("行"))
}
