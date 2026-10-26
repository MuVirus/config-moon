// JSON 严格类型测试：数字、浮点、字符串之间不做隐式转换。
//
// 这里只依赖 core 的 `Value` 和 json_format 自己的 `extract`，
// 不经过上层的 Config / StringSource。

///|
/// 把 JSON 文本解码成底层 `Value`，后面的测试统一走 `extract(Value)`。
fn json_value(text : Bytes) -> @config.Value raise @config.ConfigError {
  @json_format.JsonFormat::new().decode(text)
}

///|
/// 提取到 `Int` 字段；成功时把值也带回来，失败时给错误原文
fn int_extract_result(v : @config.Value) -> String {
  try {
    let got : IntValue = @json_format.extract(v)
    "没有报错：value = \{got.value}"
  } catch {
    error => error.to_string()
  }
}

///|
/// 提取到 `String` 字段；成功时把值也带回来，失败时给错误原文
fn text_extract_result(v : @config.Value) -> String {
  try {
    let got : TextValue = @json_format.extract(v)
    "没有报错：value = \"\{got.value}\""
  } catch {
    error => error.to_string()
  }
}

///|
struct IntValue {
  value : Int32
} derive(@json.FromJson)

///|
pub extend IntValue with @json.FromJson::{from_json}

///|
struct TextValue {
  value : String
} derive(@json.FromJson)

///|
pub extend TextValue with @json.FromJson::{from_json}

///|
struct FloatValue {
  value : Double
} derive(@json.FromJson)

///|
pub extend FloatValue with @json.FromJson::{from_json}

///|
struct Int64Value {
  value : @json_format.Int64Text
} derive(@json.FromJson)

///|
pub extend Int64Value with @json.FromJson::{from_json}

///|
struct UInt64Value {
  value : @json_format.UInt64Text
} derive(@json.FromJson)

///|
pub extend UInt64Value with @json.FromJson::{from_json}

///|
/// 浮点数提取成 `Int` 必须报错，不能静默截断成整数部分。
test "JSON float cannot be extracted as Int" {
  let v = json_value(b"{\"value\": 3.14}")
  assert_eq(
    int_extract_result(v),
    "配置项 value 类型不符：期望 Int，实际 Float",
  )
}

///|
/// 负浮点数同样不能截断。
test "negative JSON float cannot be extracted as Int" {
  let v = json_value(b"{\"value\": -3.99}")
  assert_eq(
    int_extract_result(v),
    "配置项 value 类型不符：期望 Int，实际 Float",
  )
}

///|
/// 9007199254740993 超出 Double 的精确整数范围，端到端都要保原文。
test "big int stays exact in Int64Text and UInt64Text" {
  let v = json_value(b"{\"value\": 9007199254740993}")
  let signed : Int64Value = @json_format.extract(v)
  assert_eq(signed.value.to_int64(), 9007199254740993L)
  let unsigned : UInt64Value = @json_format.extract(v)
  assert_eq(unsigned.value.to_uint64(), 9007199254740993UL)
}

///|
/// 大整数提取成 32 位 `Int` 应该报范围错误，而不是绕回或截断。
test "big int extracted as Int reports overflow" {
  let v = json_value(b"{\"value\": 9007199254740993}")
  assert_eq(
    int_extract_result(v),
    "解析失败：配置项 value 超出 Int 范围",
  )
}

///|
/// 负数大整数同样按原文还原。
test "negative big int stays exact" {
  let v = json_value(b"{\"value\": -9007199254740993}")
  let signed : Int64Value = @json_format.extract(v)
  assert_eq(signed.value.to_int64(), -9007199254740993L)
}

///|
/// 超出 Int64 的整数在解析阶段就报错，不能静默截断。
test "integer beyond Int64 is rejected while parsing" {
  let message = try {
    ignore(json_value(b"{\"value\": 9223372036854775808}"))
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    message, "解析失败：整数 9223372036854775808 超出 Int64 范围",
  )
}

///|
/// 数字来源不能提取成字符串，字符串来源不能提取成数字。
test "number and string do not cross in extraction" {
  let number = json_value(b"{\"value\": 5432}")
  assert_eq(
    text_extract_result(number),
    "配置项 value 类型不符：期望 Str，实际 Int",
  )
  let text = json_value(b"{\"value\": \"5432\"}")
  assert_eq(
    int_extract_result(text),
    "配置项 value 类型不符：期望 Int，实际 Str",
  )
}

///|
/// `Int32` 的精确边界：最大/最小值可提取，越界一位就报范围错误。
test "Int32 boundaries are strict" {
  assert_eq(
    int_extract_result(json_value(b"{\"value\": 2147483647}")),
    "没有报错：value = 2147483647",
  )
  assert_eq(
    int_extract_result(json_value(b"{\"value\": -2147483648}")),
    "没有报错：value = -2147483648",
  )
  assert_eq(
    int_extract_result(json_value(b"{\"value\": 2147483648}")),
    "解析失败：配置项 value 超出 Int 范围",
  )
  assert_eq(
    int_extract_result(json_value(b"{\"value\": -2147483649}")),
    "解析失败：配置项 value 超出 Int 范围",
  )
}

///|
/// 浮点字段也不接受字符串来源。
test "string cannot be extracted as Double" {
  let v = json_value(b"{\"value\": \"3.14\"}")
  let message = try {
    let got : FloatValue = @json_format.extract(v)
    "没有报错：value = \{got.value}"
  } catch {
    error => error.to_string()
  }
  assert_eq(message, "配置项 value 类型不符：期望 Float，实际 Str")
}

///|
/// `Int64Text` 只认整数形状：字符串和浮点都不收。
test "Int64Text rejects string and float sources" {
  let from_string = json_value(b"{\"value\": \"9007199254740993\"}")
  let string_message = try {
    let got : Int64Value = @json_format.extract(from_string)
    "没有报错：value = \{got.value.to_int64()}"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    string_message, "配置项 value 类型不符：期望 Int64，实际 Str",
  )

  let from_float = json_value(b"{\"value\": 3.14}")
  let float_message = try {
    let got : Int64Value = @json_format.extract(from_float)
    "没有报错：value = \{got.value.to_int64()}"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    float_message, "配置项 value 类型不符：期望 Int64，实际 Float",
  )
}
