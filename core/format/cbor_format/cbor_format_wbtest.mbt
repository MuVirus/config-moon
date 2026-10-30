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
/// 嵌套的array和map
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
  assert_eq(cbor_type_name(@cbor.CborValue::Unsigned(1UL)), "integer")
  assert_eq(cbor_type_name(@cbor.CborValue::Integer(-1L)), "integer")
  assert_eq(cbor_type_name(@cbor.CborValue::Bytes(b"x")), "byte string")
  assert_eq(cbor_type_name(@cbor.CborValue::Text("x")), "text")
  assert_eq(cbor_type_name(@cbor.CborValue::Array([])), "array")
  assert_eq(cbor_type_name(@cbor.CborValue::Map([])), "map")
  assert_eq(
    cbor_type_name(@cbor.CborValue::Tag(0, @cbor.CborValue::Text("x"))),
    "tagged value",
  )
  assert_eq(cbor_type_name(@cbor.CborValue::Simple(20)), "boolean")
  assert_eq(cbor_type_name(@cbor.CborValue::Simple(22)), "null")
  assert_eq(cbor_type_name(@cbor.CborValue::Simple(23)), "undefined")
  assert_eq(cbor_type_name(@cbor.CborValue::Simple(1)), "simple value")
  assert_eq(cbor_type_name(@cbor.CborValue::Float64(1.0)), "float")
}

///|
/// 解码错误的消息
test "cbor error text" {
  assert_eq(
    cbor_error_text(@cbor.CborError::UnexpectedEOF),
    "unexpected end of data",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::UnexpectedBreak),
    "unexpected break marker",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::InvalidMajorType(b'\x1c')),
    "invalid major type 28",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::InvalidAdditionalInfo(b'\x1c')),
    "invalid additional information 28",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::InvalidIndefiniteChunk(b'\x1c')),
    "invalid indefinite-length chunk header 28",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::InvalidUtf8),
    "text is not valid UTF-8",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::NonCanonicalEncoding("x")),
    "non-canonical encoding: x",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::TrailingBytes(3)),
    "trailing data: 3 byte(s) remaining",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::UnsupportedFloatWidth(b'\x1c')),
    "unsupported float width 28",
  )
  assert_eq(
    cbor_error_text(@cbor.CborError::SemanticError("x")),
    "semantic error: x",
  )
}

///|
/// 根节点不是map时报错
test "non-map root reports ParseError" {
  let message = try {
    ignore(cbor_root_to_value(@cbor.CborValue::Text("x")))
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "CBOR root must be a map, got text")
}

///|
/// 键不是text字符串时报错
test "non-string key reports ParseError" {
  let message = try {
    ignore(
      cbor_map_to_value([
        (@cbor.CborValue::Integer(1L), @cbor.CborValue::Text("x")),
      ]),
    )
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "CBOR map keys must be text strings, got integer")
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
/// 其它simple value没有对应的形状
test "other simple values have no shape" {
  let message = try {
    ignore(cbor_to_value(@cbor.CborValue::Simple(1)))
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(
    message, "CBOR simple value 1 has no corresponding Value representation",
  )
}
