///|
/// CBOR 格式：字节 → `Value`，解析交给 `2515050242/cbor`。
///
/// **根节点必须是一张映射。** 和 TOML 一样，配置是键值的集合，没有键就没法
/// 取值。根节点是数组、文本、数字都报错。
///
/// **映射的键必须是文本字符串。** 和 JSON、TOML、YAML 一致。CBOR 允许整数键，
/// 但配置里的键就是路径，路径是文本。整数键、布尔键这些一律报错，不偷偷转成
/// 字符串——那样整数键 `1` 和字符串键 `"1"` 会撞车。
///
/// **标签被剥掉。** CBOR 的标签（RFC 8949 的 major type 6）是对值的注解，
/// `Value` 里没有放标签的地方，所以只留标签里面的值。要看标签原始信息的话，
/// 自己用 `2515050242/cbor` 读。
///
/// **undefined 报错。** CBOR 的 `undefined` 和 `null` 是两个东西，`null` 落到
/// `Value::null()`，`undefined` 没有对应的形状，报错而不是悄悄当成空值。
///
/// **字节串原样保留。** CBOR 的字节串（major type 2）落到 `Value::bytes`，
/// 用 `get_bytes` 取出来就是原始字节，不会变成 base64 或别的什么。
///
/// **整数超出 `Int64` 报错。** CBOR 的无符号整数最大到 `UInt64`，塞不进
/// `Int64` 就报错，不静默降级成浮点。
///
/// **浮点都是 `Double`。** CBOR 的半精度、单精度、双精度浮点都展宽到
/// `Double`。半精度和单精度的字面量本身范围有限，展宽后不会掉精度。
///
/// 解析器还认不定长容器（RFC 8949 的 indefinite-length）、canonical 编码检查、
/// UTF-8 校验，末尾有多余字节会报错。这些的边界以 `2515050242/cbor` 为准。
pub struct CborFormat {}

///|
/// 构造 CBOR 格式
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = @config.Config::new()
///     .add(
///       @config.BytesSource::new(
///         b"\xa1\x64port\x19\x15\x38",
///         @cbor_format.CborFormat::new(),
///       ),
///     )
///     .build()
///   assert_eq(cfg.get_int("port"), 5432L)
/// }
/// ```
pub fn CborFormat::new() -> CborFormat {
  CborFormat::{ }
}

///|
pub impl @config.Format for CborFormat with fn decode(
  _ : CborFormat,
  bytes : Bytes,
) -> @config.Value raise @config.ConfigError {
  parse_cbor(bytes)
}

///|
pub extend CborFormat with @config.Format::{decode}

///|
pub impl @config.Format for CborFormat with fn suffixes(_ : CborFormat) -> Array[
  String,
] {
  ["cbor"]
}

///|
/// 首字节的 major type 是 map（5）就像 CBOR。
pub impl @config.Format for CborFormat with fn sniff(
  _ : CborFormat,
  bytes : Bytes,
) -> Bool {
  if bytes.is_empty() {
    return false
  }
  ((bytes[0].to_int() >> 5) & 0x07) == 5
}

///|
pub extend CborFormat with @config.Format::{decode_path, suffixes, sniff}

///|
/// CBOR 字节 → `Value`。
fn parse_cbor(bytes : Bytes) -> @config.Value raise @config.ConfigError {
  let decoded = @cbor.decode(bytes) catch {
    e => raise @config.ConfigError::ParseError(cbor_error_text(e))
  }
  cbor_root_to_value(decoded)
}

///|
/// 根节点 → `Value`。根节点必须是一张映射。
fn cbor_root_to_value(
  v : @cbor.CborValue,
) -> @config.Value raise @config.ConfigError {
  match v {
    @cbor.CborValue::Map(pairs) => cbor_map_to_value(pairs)
    v =>
      raise @config.ConfigError::ParseError(
        "CBOR root must be a map, got \{cbor_type_name(v)}",
      )
  }
}

///|
/// 映射 → `Value`。键必须是文本字符串。
fn cbor_map_to_value(
  pairs : Array[(@cbor.CborValue, @cbor.CborValue)],
) -> @config.Value raise @config.ConfigError {
  let out : Map[String, @config.Value] = Map([])
  for (k, v) in pairs {
    match k {
      @cbor.CborValue::Text(name) => out[name] = cbor_to_value(v)
      k =>
        raise @config.ConfigError::ParseError(
          "CBOR map keys must be text strings, got \{cbor_type_name(k)}",
        )
    }
  }
  @config.Value::table(out)
}

///|
/// `CborValue` → `Value`。
fn cbor_to_value(
  v : @cbor.CborValue,
) -> @config.Value raise @config.ConfigError {
  match v {
    @cbor.CborValue::Unsigned(u) =>
      if u <= 0x7FFFFFFFFFFFFFFFUL {
        @config.Value::int(u.reinterpret_as_int64())
      } else {
        raise @config.ConfigError::ParseError(
          "integer \{u} exceeds Int64 range",
        )
      }
    @cbor.CborValue::Integer(i) => @config.Value::int(i)
    @cbor.CborValue::Bytes(b) => @config.Value::bytes(b)
    @cbor.CborValue::Text(s) => @config.Value::str(s)
    @cbor.CborValue::Array(arr) => @config.Value::array(arr.map(cbor_to_value))
    @cbor.CborValue::Map(pairs) => cbor_map_to_value(pairs)
    @cbor.CborValue::Tag(_, inner) => cbor_to_value(inner)
    @cbor.CborValue::Simple(20) => @config.Value::bool(false)
    @cbor.CborValue::Simple(21) => @config.Value::bool(true)
    @cbor.CborValue::Simple(22) => @config.Value::null()
    @cbor.CborValue::Simple(23) =>
      raise @config.ConfigError::ParseError(
        "CBOR undefined has no corresponding Value representation",
      )
    @cbor.CborValue::Simple(n) =>
      raise @config.ConfigError::ParseError(
        "CBOR simple value \{n.to_int()} has no corresponding Value representation",
      )
    @cbor.CborValue::Float64(f) => @config.Value::float(f)
  }
}

///|
/// 值的形状名字，报错时用（「实际是整数」里的那个词）。
fn cbor_type_name(v : @cbor.CborValue) -> String {
  match v {
    @cbor.CborValue::Unsigned(_) | @cbor.CborValue::Integer(_) => "integer"
    @cbor.CborValue::Bytes(_) => "byte string"
    @cbor.CborValue::Text(_) => "text"
    @cbor.CborValue::Array(_) => "array"
    @cbor.CborValue::Map(_) => "map"
    @cbor.CborValue::Tag(_, _) => "tagged value"
    @cbor.CborValue::Simple(20) | @cbor.CborValue::Simple(21) => "boolean"
    @cbor.CborValue::Simple(22) => "null"
    @cbor.CborValue::Simple(23) => "undefined"
    @cbor.CborValue::Simple(_) => "simple value"
    @cbor.CborValue::Float64(_) => "float"
  }
}

///|
/// 解码错误的消息。
fn cbor_error_text(e : @cbor.CborError) -> String {
  match e {
    @cbor.CborError::UnexpectedEOF => "unexpected end of data"
    @cbor.CborError::UnexpectedBreak => "unexpected break marker"
    @cbor.CborError::InvalidMajorType(b) => "invalid major type \{b.to_int()}"
    @cbor.CborError::InvalidAdditionalInfo(b) =>
      "invalid additional information \{b.to_int()}"
    @cbor.CborError::InvalidIndefiniteChunk(b) =>
      "invalid indefinite-length chunk header \{b.to_int()}"
    @cbor.CborError::InvalidUtf8 => "text is not valid UTF-8"
    @cbor.CborError::NonCanonicalEncoding(s) => "non-canonical encoding: \{s}"
    @cbor.CborError::TrailingBytes(n) => "trailing data: \{n} byte(s) remaining"
    @cbor.CborError::UnsupportedFloatWidth(b) =>
      "unsupported float width \{b.to_int()}"
    @cbor.CborError::SemanticError(s) => "semantic error: \{s}"
  }
}
