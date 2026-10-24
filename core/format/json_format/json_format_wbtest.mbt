// Whitebox tests for the json package: the number handling has all the
// sharp edges, so most of these pin down its behaviour.

///|
using @config {type ConfigError, type Value, type ValueKind}

///|
/// 只用来验证提取失败会报错，不满足就炸
struct NeedsHost {
  host : String
} derive(@json.FromJson)

///|
pub extend NeedsHost with @json.FromJson::{from_json}

///|
/// 只用来验证字节串能提取到结构体的 `Bytes` 字段
struct NeedsBlob {
  blob : Bytes
} derive(@json.FromJson)

///|
pub extend NeedsBlob with @json.FromJson::{from_json}

///|
/// `Bytes` 字段能从 `Value` 里原样提取出来
test "extract reads bytes into a Bytes field" {
  let raw = b"\x00\x01abcd"
  let got : NeedsBlob = extract(Value::table({ "blob": Value::bytes(raw) }))
  assert_eq(got.blob, raw)
}

///|
/// Json → Value：整数、浮点、大整数、嵌套结构都要按规矩拆
test "json_to_value" {
  let json = @json.parse(
    "{\"i\": -42, \"f\": 1.5, \"t\": true, \"big\": 9007199254740993, \"n\": null, \"a\": [1, \"x\"]}",
  )
  let value = json_to_value(json)
  assert_eq(value.get_path("i").kind, ValueKind::Int(-42L))
  assert_eq(value.get_path("f").kind, ValueKind::Float(1.5))
  assert_eq(value.get_path("t").kind, ValueKind::Bool(true))
  assert_eq(value.get_path("big").kind, ValueKind::Int(9007199254740993L))
  assert_eq(value.get_path("n").kind, ValueKind::Null)
  assert_eq(
    value.get_path("a").kind,
    ValueKind::Array([Value::int(1L), Value::str("x")]),
  )
}

///|
/// 原文丢了只能看值：写了小数点／指数的整数值也按整数算（已知取舍）
test "json_to_value integral floats" {
  let value = json_to_value(
    @json.parse("{\"a\": 1.0, \"b\": 1e2, \"c\": -0.5e1}"),
  )
  assert_eq(value.get_path("a").kind, ValueKind::Int(1L))
  assert_eq(value.get_path("b").kind, ValueKind::Int(100L))
  assert_eq(value.get_path("c").kind, ValueKind::Int(-5L))
}

///|
/// 塞不进 Int64 的整数直接报错，不静默截断
test "json_to_value rejects oversized int" {
  let value = try {
    ignore(json_to_value(@json.parse("99999999999999999999")))
    false
  } catch {
    ConfigError::ParseError(_) => true
    _ => false
  }
  assert_true(value)
}

///|
/// 超范围的浮点字面量（`1e999`）要变成浮点，不能去喂整数解析器
///
/// 这条是被真 bug 逼出来的：`BigInt::from_string("1e999")` 不会抛错，
/// 而是直接 `abort` 整个进程——配置里一个数字就能把程序打崩。
test "json_to_value handles oversized float" {
  let value = json_to_value(
    @json.parse("{\"a\": 1e999, \"b\": -1e999, \"c\": 1.5e400}"),
  )
  assert_eq(value.get_path("a").kind, ValueKind::Float(@double.infinity))
  assert_eq(value.get_path("b").kind, ValueKind::Float(@double.neg_infinity))
  assert_eq(value.get_path("c").kind, ValueKind::Float(@double.infinity))
}

///|
/// 字面量分流：只有纯整数形式才喂给 Int64 解析器
test "is_integer_literal" {
  assert_true(is_integer_literal("0"))
  assert_true(is_integer_literal("-42"))
  assert_true(is_integer_literal("9007199254740993"))
  assert_false(is_integer_literal("1.0"))
  assert_false(is_integer_literal("1e2"))
  assert_false(is_integer_literal("1.5E-3"))
}

///|
/// 整数值、且塞得进 Int64 才算整数
test "is_int64" {
  assert_true(is_int64(0.0))
  assert_true(is_int64(-42.0))
  assert_true(is_int64(1.0e18))
  assert_false(is_int64(1.5))
  assert_false(is_int64(@double.infinity))
  assert_false(is_int64(@double.not_a_number))
  assert_false(is_int64(1.0e19)) // 超出 Int64 范围
}

///|
/// Value → Json：`Int` 走数字，同时带 `repr` 保住原文
test "to_json keeps int as number with repr" {
  assert_eq(
    to_json(Value::int(9007199254740993L)),
    Json::number(9007199254740992.0, repr="9007199254740993"),
  )
  assert_eq(to_json(Value::float(1.5)), Json::number(1.5))
  assert_eq(to_json(Value::null()), Json::null())
  assert_eq(to_json(Value::bool(true)), Json::boolean(true))
  assert_eq(to_json(Value::str("x")), Json::string("x"))
  assert_eq(
    to_json(Value::array([Value::int(1L)])),
    Json::array([Json::number(1.0, repr="1")]),
  )
  assert_eq(
    to_json(Value::table({ "a": Value::bool(false) })),
    Json::object({ "a": Json::boolean(false) }),
  )
}

///|
/// `repr` 让 stringify 也保持原文
test "to_json int stringify keeps exact text" {
  assert_eq(
    to_json(Value::int(9007199254740993L)).stringify(),
    "9007199254740993",
  )
}

///|
/// Value → Json：`Bytes` 走 core 的字节编码，和 `FromJson for Bytes` 对称
test "to_json keeps bytes and they round-trip" {
  let raw = b"\x00\x01abcd\"\\"
  assert_eq(
    to_json(Value::bytes(raw)),
    Json::string("\\x00\\x01abcd\\x22\\x5c"),
  )
  let back : Bytes = @json.from_json(to_json(Value::bytes(raw))) catch {
    _ => b""
  }
  assert_eq(back, raw)
}

///|
/// 字段缺失报 MissingKey，类型不符报 TypeMismatch，不能静默变默认值
test "extract reports shape mismatch" {
  let good : NeedsHost = extract(Value::table({ "host": Value::str("x") }))
  assert_eq(good.host, "x")
  let missing = try {
    let bad : NeedsHost = extract(Value::table({ "port": Value::int(1L) }))
    ignore(bad)
    false
  } catch {
    ConfigError::MissingKey(path) => path == "host"
    _ => false
  }
  assert_true(missing)
  let mismatch = try {
    let bad : NeedsHost = extract(Value::table({ "host": Value::int(1L) }))
    ignore(bad)
    false
  } catch {
    ConfigError::TypeMismatch(path, expected, actual) =>
      path == "host" && expected == "Str" && actual == "Int"
    _ => false
  }
  assert_true(mismatch)
}

///|
/// 64 位包装类型只认整数，字符串和浮点都不收
test "Int64Text rejects non-integer shapes" {
  let from_string = try {
    let bad : Int64Text = @json.from_json(Json::string("5432"))
    ignore(bad)
    false
  } catch {
    @json.JsonDecodeError(_) => true
  }
  assert_true(from_string)
  let from_float = try {
    let bad : Int64Text = @json.from_json(Json::number(1.5))
    ignore(bad)
    false
  } catch {
    @json.JsonDecodeError(_) => true
  }
  assert_true(from_float)
}

///|
/// 大整数、负数和 UInt64 都按原文还原
test "Int64Text and UInt64Text parse exactly" {
  let big : Int64Text = @json.from_json(
    to_json(Value::int(-9223372036854775807L)),
  )
  assert_eq(big.to_int64(), -9223372036854775807L)
  let unsigned : UInt64Text = @json.from_json(
    to_json(Value::int(9007199254740993L)),
  )
  assert_eq(unsigned.to_uint64(), 9007199254740993UL)
}

///|
/// JSON Pointer 的段要按 RFC 6901 反转义
test "pointer_segments" {
  assert_eq(pointer_segments(""), [])
  assert_eq(pointer_segments("/db/port"), ["db", "port"])
  assert_eq(pointer_segments("/a~1b/c~0d"), ["a/b", "c~d"])
  assert_eq(index_of("0"), Some(0))
  assert_eq(index_of("12"), Some(12))
  assert_eq(index_of("-1"), None)
  assert_eq(index_of("x"), None)
}

///|
/// 按键路径反查实际类型
test "value_at" {
  let v = Value::table({
    "db": Value::table({
      "port": Value::int(1L),
      "list": Value::array([Value::str("x")]),
    }),
  })
  assert_eq(value_at(v, ["db", "port"]).unwrap().kind, ValueKind::Int(1L))
  assert_eq(value_at(v, ["db", "list", "0"]).unwrap().kind, ValueKind::Str("x"))
  assert_eq(value_at(v, ["db", "nope"]), None)
}
