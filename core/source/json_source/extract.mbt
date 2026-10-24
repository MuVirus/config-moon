// 提取到结构体：`Value` → `Json` → `FromJson`。
//
// 整数的映射和错误消息都在这里收口：
// - 整数映射成 `Json::Number`，大整数靠 `repr` 保住原文（见 `to_json`）
// - `derive(FromJson)` 的报错反查回 `Value`，统一成 `ConfigError`

///|
/// 结构体里的 64 位整数字段。
///
/// core 的 `FromJson for Int64` 只接受 JSON 字符串，而本库把整数映射成
/// JSON 数字，所以结构体里不能直接写 `port : Int64`。改成
/// `port : Int64Text`，它直接读 `Json::Number` 的 `repr`，大整数不丢：
///
/// ```mbt check
/// test {
///   let json = @json_source.to_json(@config.Value::int(9007199254740993L))
///   let id : @json_source.Int64Text = @json.from_json(json)
///   assert_eq(id.to_int64(), 9007199254740993L)
/// }
/// ```
///
/// 全精度的另一条路是按键取值：`get_int` 直接返回 `Int64`。
pub struct Int64Text {
  value : Int64
} derive(Eq)

///|
pub extend Int64Text with Eq::{equal, not_equal}

///|
pub fn Int64Text::new(value : Int64) -> Int64Text {
  { value, }
}

///|
pub fn Int64Text::to_int64(self : Int64Text) -> Int64 {
  self.value
}

///|
/// 只认 `Value::int` 映射出来的数字：它一定带 `repr`。
/// 字符串、浮点都不收，否则就成了隐式转换。
pub impl @json.FromJson for Int64Text with fn from_json(json, path) {
  let text = match json {
    Json::Number(_, repr~) =>
      match repr {
        Some(text) => text
        None =>
          raise @json.JsonDecodeError(
            (path, "Int64::from_json: expected integer"),
          )
      }
    _ =>
      raise @json.JsonDecodeError((path, "Int64::from_json: expected integer"))
  }
  if !is_integer_literal(text) {
    raise @json.JsonDecodeError((path, "Int64::from_json: expected integer"))
  }
  {
    value: int64_of(text) catch {
      @config.ConfigError::ParseError(message) =>
        raise @json.JsonDecodeError((path, message))
      error => raise @json.JsonDecodeError((path, error.to_string()))
    },
  }
}

///|
pub extend Int64Text with @json.FromJson::{from_json}

///|
pub impl @json.ToJson for Int64Text with fn to_json(self) {
  Json::number(self.value.to_double(), repr=self.value.to_string())
}

///|
pub extend Int64Text with @json.ToJson::{to_json}

///|
/// 结构体里的无符号 64 位整数字段，用法同 `Int64Text`。
pub struct UInt64Text {
  value : UInt64
} derive(Eq)

///|
pub extend UInt64Text with Eq::{equal, not_equal}

///|
pub fn UInt64Text::new(value : UInt64) -> UInt64Text {
  { value, }
}

///|
pub fn UInt64Text::to_uint64(self : UInt64Text) -> UInt64 {
  self.value
}

///|
pub impl @json.FromJson for UInt64Text with fn from_json(json, path) {
  let text = match json {
    Json::Number(_, repr~) =>
      match repr {
        Some(text) => text
        None =>
          raise @json.JsonDecodeError(
            (path, "UInt64::from_json: expected integer"),
          )
      }
    _ =>
      raise @json.JsonDecodeError((path, "UInt64::from_json: expected integer"))
  }
  if !is_integer_literal(text) || text.contains("-") {
    raise @json.JsonDecodeError(
      (path, "UInt64::from_json: expected non-negative integer"),
    )
  }
  let big = @bigint.BigInt::from_string(text)
  if big.compare_uint64(18446744073709551615UL) > 0 {
    raise @json.JsonDecodeError((path, "UInt64::from_json: overflow"))
  }
  { value: big.to_uint64(), }
}

///|
pub extend UInt64Text with @json.FromJson::{from_json}

///|
pub impl @json.ToJson for UInt64Text with fn to_json(self) {
  Json::number(self.value.to_double(), repr=self.value.to_string())
}

///|
pub extend UInt64Text with @json.ToJson::{to_json}

///|
/// 提取到结构体：`Value` → `Json` → `FromJson`。
///
/// 用户的类型用编译器自带的 `derive(FromJson)`。
pub fn[T : @json.FromJson] extract(
  v : @config.Value,
) -> T raise @config.ConfigError {
  extract_at(v, "")
}

///|
/// 取配置里某个路径的值并提取成用户结构体。
///
/// 原来是 `Config::extract`，拆分时降级成自由函数——理由同 `to_json`。
pub fn[T : @json.FromJson] extract_from(
  cfg : @config.Config,
  path : String,
) -> T raise @config.ConfigError {
  extract_at(cfg.get_value(path), path)
}

///|
/// 提取失败时把 core 的错误翻成库自己的错误：
/// 键名、期望类型、实际类型，和 `get_*` 一个口径。
fn[T : @json.FromJson] extract_at(
  v : @config.Value,
  prefix : String,
) -> T raise @config.ConfigError {
  @json.from_json(to_json(v)) catch {
    @json.JsonDecodeError((path, message)) =>
      raise explain(v, prefix, path, message)
  }
}

///|
fn explain(
  v : @config.Value,
  prefix : String,
  path : @json.JsonPath,
  message : String,
) -> @config.ConfigError {
  // JsonPath 的 Show 是 JSON Pointer（`/db/port`），直接拿来当路径用
  let segments = pointer_segments(path.to_string())
  let key = join_key(prefix, segments)
  let marker = "Missing field "
  if message.has_prefix(marker) {
    let field = message[marker.length():].to_owned()
    return @config.ConfigError::MissingKey(
      if key == "(根)" {
        field
      } else {
        "\{key}.\{field}"
      },
    )
  }
  let expected = expected_name(message)
  let actual = match value_at(v, segments) {
    Some(found) => found.kind.name()
    None => "未知"
  }
  if message.contains("number in string representation") {
    // 结构体里写了 `Int64`：换个类型就能取，不是数据的问题
    return @config.ConfigError::ParseError(
      "配置项 \{key} 是 64 位整数：结构体字段请声明为 Int64Text，或改用 get_int",
    )
  }
  if message.contains("overflow") {
    return @config.ConfigError::ParseError(
      "配置项 \{key} 超出 \{expected} 范围",
    )
  }
  @config.ConfigError::TypeMismatch(key, expected, actual)
}

///|
/// core 的 `Xxx::from_json: ...` → 库里的类型名
fn expected_name(message : String) -> String {
  if message.has_prefix("Expected object") {
    return "Table"
  }
  if message.has_prefix("Expected array") {
    return "Array"
  }
  let name = match message.find("::") {
    Some(index) => message[:index].to_owned()
    None => "Json"
  }
  match name {
    "String" => "Str"
    "Double" | "Float" => "Float"
    "Map" => "Table"
    "Unit" => "Null"
    _ => name
  }
}

///|
/// JSON Pointer → 路径段，按 RFC 6901 反转义
fn pointer_segments(pointer : String) -> Array[String] {
  let segments : Array[String] = []
  for part in pointer.split("/") {
    let segment = part.to_owned()
    if segment == "" {
      continue
    }
    segments.push(unescape_token(segment))
  }
  segments
}

///|
fn unescape_token(token : String) -> String {
  token.replace_all(old="~1", new="/").replace_all(old="~0", new="~")
}

///|
fn join_key(prefix : String, segments : Array[String]) -> String {
  let mut key = prefix
  for segment in segments {
    key = if key == "" { segment } else { "\{key}.\{segment}" }
  }
  if key == "" {
    "(根)"
  } else {
    key
  }
}

///|
/// 按路径段在 `Value` 上走一遍，用来报“实际类型”
fn value_at(v : @config.Value, segments : Array[String]) -> @config.Value? {
  let mut current = v
  for segment in segments {
    let next = match current.kind {
      @config.ValueKind::Table(table) => table.get(segment)
      @config.ValueKind::Array(items) =>
        match index_of(segment) {
          Some(index) if index >= 0 && index < items.length() =>
            Some(items[index])
          _ => None
        }
      _ => None
    }
    match next {
      Some(found) => current = found
      None => return None
    }
  }
  Some(current)
}

///|
fn index_of(segment : String) -> Int32? {
  if segment == "" {
    return None
  }
  let mut index = 0
  for ch in segment {
    if ch < '0' || ch > '9' {
      return None
    }
    index = index * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(index)
}
