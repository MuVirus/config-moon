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
/// 嵌套结构，用来验证 MissingKey 会拼上父路径
#warnings("-unused_field")
struct NestedNeedsHost {
  db : NeedsHost
} derive(@json.FromJson)

///|
pub extend NestedNeedsHost with @json.FromJson::{from_json}

///|
/// 整型数组，用来验证浮点探针会递归进数组
#warnings("-unused_field")
struct IntArrayCfg {
  values : Array[Int32]
} derive(@json.FromJson)

///|
pub extend IntArrayCfg with @json.FromJson::{from_json}

///|
/// 数组字段，用来验证对象/数组形状错误
#warnings("-unused_field")
struct StringListCfg {
  values : Array[String]
} derive(@json.FromJson)

///|
pub extend StringListCfg with @json.FromJson::{from_json}

///|
/// `Bytes` 字段能从 `Value` 里原样提取出来
test "extract reads bytes into a Bytes field" {
  let raw = b"\x00\x01abcd"
  let got : NeedsBlob = extract(Value::table({ "blob": Value::bytes(raw) }))
  assert_eq(got.blob, raw)
}

///|
/// 字符串来源不能提取到 `Bytes` 字段，即使内容看起来像字节编码
test "string is not extracted as Bytes" {
  let message = try {
    let _ : NeedsBlob = extract(Value::table({ "blob": Value::str("hello") }))
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(message, "配置项 blob 类型不符：期望 Bytes，实际 Str")
}

///|
/// 字节来源也不能提取到 `String` 字段
test "Bytes are not extracted as String" {
  let message = try {
    let _ : NeedsHost = extract(
      Value::table({ "host": Value::bytes(b"hello") }),
    )
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(message, "配置项 host 类型不符：期望 Str，实际 Bytes")
}

///|
/// `"NaN"` 这种特殊浮点字符串在 `String` 字段里仍然是字符串
test "special float strings stay strings" {
  let got : NeedsHost = extract(Value::table({ "host": Value::str("NaN") }))
  assert_eq(got.host, "NaN")
}

///|
/// 非法 UTF-8 应该在解码阶段报 ParseError，而不是交给 JSON 解析器
test "decode rejects invalid UTF-8" {
  let message = try {
    ignore(JsonFormat::new().decode(b"\xff"))
    "没有报错"
  } catch {
    ConfigError::ParseError(message) => message
    error => error.to_string()
  }
  assert_eq(message, "JSON 内容不是合法的 UTF-8")
}

///|
/// sniff 跳过前导空白，空白串和标量根都不算 JSON 对象/数组
test "sniff skips leading whitespace" {
  let format = JsonFormat::new()
  assert_true(format.sniff(b" \t\r\n{\"a\":1}"))
  assert_true(format.sniff(b" \t\r\n[1]"))
  assert_false(format.sniff(b" \t\r\n"))
  assert_false(format.sniff(b"true"))
}

///|
/// Json::False 也要映射成 Bool(false)
test "json_to_value decodes false" {
  let value = json_to_value(@json.parse("false"))
  assert_eq(value.kind, ValueKind::Bool(false))
}

///|
/// 嵌套字段缺失时，路径要带上父级，而不是只报字段名
test "extract reports nested missing field" {
  let message = try {
    let _ : NestedNeedsHost = extract(
      Value::table({ "db": Value::table({ "other": Value::int(1L) }) }),
    )
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    message, "配置项 db.host 不存在：没有任何来源提供它",
  )
}

///|
/// 数组里的浮点也必须被浮点探针拦住，不能只检查表字段
test "extract rejects float inside Int array" {
  let value = Value::table({
    "values": Value::array([Value::int(1L), Value::float(2.5)]),
  })
  assert_true(has_float(value))
  let message = try {
    let _ : IntArrayCfg = extract(value)
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    message, "配置项 values.1 类型不符：期望 Int，实际 Float",
  )
}

///|
/// Json → Value：整数、浮点、大整数、嵌套结构都要按规矩拆
test "json_to_value" {
  let json = @json.parse(
    "{\"i\": -42, \"f\": 1.5, \"t\": true, \"big\": 9007199254740993, \"n\": null, \"a\": [1, \"x\"]}",
    preserve_number_repr=true,
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
/// 有没有小数点／指数决定形状：值是整数也必须留作 Float
test "json_to_value keeps integral floats as Float" {
  let value = json_to_value(
    @json.parse(
      "{\"a\": 1.0, \"b\": 1e2, \"c\": -0.5e1, \"d\": -0.0}",
      preserve_number_repr=true,
    ),
  )
  assert_eq(value.get_path("a").kind, ValueKind::Float(1.0))
  assert_eq(value.get_path("b").kind, ValueKind::Float(100.0))
  assert_eq(value.get_path("c").kind, ValueKind::Float(-5.0))
  assert_eq(value.get_path("d").kind, ValueKind::Float(-0.0))
}

///|
/// 没有原文时按浮点处理，不能靠数值是否完整反推成整数
test "json_to_value without repr stays Float" {
  let value = json_to_value(@json.parse("1.0"))
  assert_eq(value.kind, ValueKind::Float(1.0))
}

///|
/// 塞不进 Int64 的整数直接报错，不静默截断
test "json_to_value rejects oversized int" {
  let value = try {
    ignore(
      json_to_value(
        @json.parse("99999999999999999999", preserve_number_repr=true),
      ),
    )
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
    @json.parse(
      "{\"a\": 1e999, \"b\": -1e999, \"c\": 1.5e400}",
      preserve_number_repr=true,
    ),
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
/// 对象/数组形状错误也要走 expected_name 的 Table / Array 分支
test "extract reports object and array shape mismatches" {
  let object_message = try {
    let _ : NeedsHost = extract(Value::array([Value::int(1L)]))
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    object_message, "配置项 (根) 类型不符：期望 Table，实际 Array",
  )

  let array_message = try {
    let _ : StringListCfg = extract(
      Value::table({ "values": Value::str("not-an-array") }),
    )
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    array_message, "配置项 values 类型不符：期望 Array，实际 Str",
  )
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
