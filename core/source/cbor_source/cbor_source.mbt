///|
/// CBOR 来源：字节 → `Value`，解析交给 `2515050242/cbor`。
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
pub struct CborSource {
  bytes : Bytes
}

///|
/// 从 CBOR 字节构造
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = @config.Config::new()
///     .add(@cbor_source.CborSource::from_bytes(b"\xa1\x64port\x19\x15\x38"))
///     .build()
///   assert_eq(cfg.get_int("port"), 5432L)
/// }
/// ```
pub fn CborSource::from_bytes(bytes : Bytes) -> CborSource {
  CborSource::{ bytes, }
}

///|
pub impl @config.Source for CborSource with fn collect(self : CborSource) -> @config.Value raise @config.ConfigError {
  parse_cbor(self.bytes)
}

///|
pub extend CborSource with @config.Source::{collect}

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
        "CBOR 的根节点必须是映射，实际是 \{cbor_type_name(v)}",
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
          "CBOR 的映射键必须是文本字符串，实际是 \{cbor_type_name(k)}",
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
        raise @config.ConfigError::ParseError("整数 \{u} 超出 Int64 范围")
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
        "CBOR 的 undefined 在 Value 里没有对应形状",
      )
    @cbor.CborValue::Simple(n) =>
      raise @config.ConfigError::ParseError(
        "CBOR 的简单值 \{n.to_int()} 在 Value 里没有对应形状",
      )
    @cbor.CborValue::Float64(f) => @config.Value::float(f)
  }
}

///|
/// 值的形状名字，报错时用（「实际是整数」里的那个词）。
fn cbor_type_name(v : @cbor.CborValue) -> String {
  match v {
    @cbor.CborValue::Unsigned(_) | @cbor.CborValue::Integer(_) => "整数"
    @cbor.CborValue::Bytes(_) => "字节串"
    @cbor.CborValue::Text(_) => "文本"
    @cbor.CborValue::Array(_) => "数组"
    @cbor.CborValue::Map(_) => "映射"
    @cbor.CborValue::Tag(_, _) => "带标签的值"
    @cbor.CborValue::Simple(20) | @cbor.CborValue::Simple(21) => "布尔"
    @cbor.CborValue::Simple(22) => "空值"
    @cbor.CborValue::Simple(23) => "未定义"
    @cbor.CborValue::Simple(_) => "简单值"
    @cbor.CborValue::Float64(_) => "浮点数"
  }
}

///|
/// 解码错误的消息。
fn cbor_error_text(e : @cbor.CborError) -> String {
  match e {
    @cbor.CborError::UnexpectedEOF => "数据意外结束"
    @cbor.CborError::UnexpectedBreak => "出现了不该有的 break 标记"
    @cbor.CborError::InvalidMajorType(b) => "非法的主类型 \{b.to_int()}"
    @cbor.CborError::InvalidAdditionalInfo(b) =>
      "非法的附加信息 \{b.to_int()}"
    @cbor.CborError::InvalidIndefiniteChunk(b) =>
      "非法的分段块首字节 \{b.to_int()}"
    @cbor.CborError::InvalidUtf8 => "文本不是合法的 UTF-8"
    @cbor.CborError::NonCanonicalEncoding(s) => "不是规范的编码：\{s}"
    @cbor.CborError::TrailingBytes(n) =>
      "数据末尾还有 \{n} 个字节没读完"
    @cbor.CborError::UnsupportedFloatWidth(b) =>
      "不支持的浮点宽度 \{b.to_int()}"
    @cbor.CborError::SemanticError(s) => "语义错误：\{s}"
  }
}
