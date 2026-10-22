// Whitebox tests for the cbor package: conversion edges live here.

///|
using @config {type ConfigError, type Value}

///|
/// 各个 CborValue 分支都能落到 Value
test "cbor variants convert to value kinds" {
  let v = parse_cbor(
    b"\xa8\x61i\x18\x2a\x61f\xfb\x3f\xf8\x00\x00\x00\x00\x00\x00\x61s\x62hi\x61b\xf5\x61n\xf6\x63arr\x82\x01\x02\x61m\xa1\x61k\x61v\x64blob\x43\x01\x02\xff",
  )
  assert_eq(
    v,
    Value::table({
      "i": Value::int(42L),
      "f": Value::float(1.5),
      "s": Value::str("hi"),
      "b": Value::bool(true),
      "n": Value::null(),
      "arr": Value::array([Value::int(1L), Value::int(2L)]),
      "m": Value::table({ "k": Value::str("v") }),
      "blob": Value::bytes(b"\x01\x02\xff"),
    }),
  )
}

///|
/// false 和 null 也落到位
test "cbor false and null convert" {
  let v = parse_cbor(b"\xa2\x61b\xf4\x61n\xf6")
  assert_eq(v, Value::table({ "b": Value::bool(false), "n": Value::null() }))
}

///|
/// 嵌套的数组和映射
test "nested containers convert" {
  let v = parse_cbor(b"\xa1\x67numbers\x83\x01\x82\x02\x03\xa1\x61k\x61v")
  assert_eq(
    v,
    Value::table({
      "numbers": Value::array([
        Value::int(1L),
        Value::array([Value::int(2L), Value::int(3L)]),
        Value::table({ "k": Value::str("v") }),
      ]),
    }),
  )
}

///|
/// 形状的名字
test "cbor type names" {
  assert_eq(cbor_type_name(@cbor.CborValue::Unsigned(1UL)), "整数")
  assert_eq(cbor_type_name(@cbor.CborValue::Integer(-1L)), "整数")
  assert_eq(cbor_type_name(@cbor.CborValue::Bytes(b"x")), "字节串")
  assert_eq(cbor_type_name(@cbor.CborValue::Text("x")), "文本")
  assert_eq(cbor_type_name(@cbor.CborValue::Array([])), "数组")
  assert_eq(cbor_type_name(@cbor.CborValue::Map([])), "映射")
  assert_eq(
    cbor_type_name(@cbor.CborValue::Tag(0, @cbor.CborValue::Text("x"))),
    "带标签的值",
  )
  assert_eq(cbor_type_name(@cbor.CborValue::Simple(20)), "布尔")
  assert_eq(cbor_type_name(@cbor.CborValue::Simple(22)), "空值")
  assert_eq(cbor_type_name(@cbor.CborValue::Simple(23)), "未定义")
  assert_eq(cbor_type_name(@cbor.CborValue::Simple(1)), "简单值")
  assert_eq(cbor_type_name(@cbor.CborValue::Float64(1.0)), "浮点数")
}

///|
/// 解码错误的消息
test "cbor error text" {
  assert_eq(
    cbor_error_text(@cbor.CborError::UnexpectedEOF),
    "数据意外结束",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::UnexpectedBreak),
    "出现了不该有的 break 标记",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::InvalidMajorType(b'\x1c')),
    "非法的主类型 28",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::InvalidAdditionalInfo(b'\x1c')),
    "非法的附加信息 28",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::InvalidIndefiniteChunk(b'\x1c')),
    "非法的分段块首字节 28",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::InvalidUtf8),
    "文本不是合法的 UTF-8",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::NonCanonicalEncoding("x")),
    "不是规范的编码：x",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::TrailingBytes(3)),
    "数据末尾还有 3 个字节没读完",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::UnsupportedFloatWidth(b'\x1c')),
    "不支持的浮点宽度 28",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::SemanticError("x")),
    "语义错误：x",
  )
}

///|
/// 根节点不是映射时报错
test "non-map root reports ParseError" {
  let message = try {
    ignore(cbor_root_to_value(@cbor.CborValue::Text("x")))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "CBOR 的根节点必须是映射，实际是 文本")
}

///|
/// 键不是文本字符串时报错
test "non-string key reports ParseError" {
  let message = try {
    ignore(
      cbor_map_to_value([
        (@cbor.CborValue::Integer(1L), @cbor.CborValue::Text("x")),
      ]),
    )
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(
    message, "CBOR 的映射键必须是文本字符串，实际是 整数",
  )
}

///|
/// 标签被剥掉
test "tags are unwrapped" {
  let v = cbor_to_value(
    @cbor.CborValue::Tag(1, @cbor.CborValue::Integer(1600000000L)),
  )
  assert_eq(v, Value::int(1600000000L))
}

///|
/// 其它简单值没有对应的形状
test "other simple values have no shape" {
  let message = try {
    ignore(cbor_to_value(@cbor.CborValue::Simple(1)))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "CBOR 的简单值 1 在 Value 里没有对应形状")
}
