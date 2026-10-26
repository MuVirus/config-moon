///|
/// JSON 格式：文本 → `Value`，用 core 的 `@json`，零第三方依赖。
pub struct JsonFormat {}

///|
/// 构造 JSON 格式
pub fn JsonFormat::new() -> JsonFormat {
  JsonFormat::{ }
}

///|
pub impl @config.Format for JsonFormat with fn decode(
  _ : JsonFormat,
  bytes : Bytes,
) -> @config.Value raise @config.ConfigError {
  let text = @utf8.decode(bytes) catch {
    _ =>
      raise @config.ConfigError::ParseError("JSON 内容不是合法的 UTF-8")
  }
  // 保留每个数字的原文：核心库默认只在超出 Double 精确范围时才留 `repr`，
  // 那会把 `1.0`、`1e2` 这种浮点写法误判成整数。
  let json = @json.parse(text, preserve_number_repr=true) catch {
    e => raise @config.ConfigError::ParseError(e.to_string())
  }
  json_to_value(json)
}

///|
pub extend JsonFormat with @config.Format::{decode}

///|
pub impl @config.Format for JsonFormat with fn suffixes(_ : JsonFormat) -> Array[
  String,
] {
  ["json"]
}

///|
/// 第一个非空白字符是 `{` 或 `[` 就像 JSON。
pub impl @config.Format for JsonFormat with fn sniff(
  _ : JsonFormat,
  bytes : Bytes,
) -> Bool {
  for byte in bytes {
    let code = byte.to_int()
    if code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D {
      continue
    }
    return code == 0x7B || code == 0x5B
  }
  false
}

///|
pub extend JsonFormat with @config.Format::{decode_path, suffixes, sniff}

///|
/// `Json` → `Value`：数字按字面量形状分成 `Int` / `Float`，整数一律 `Int64`。
///
/// `decode` 用 `preserve_number_repr=true` 解析，每个数字的原文都留在
/// `Json::Number` 的 `repr` 里。所以 `1.0`、`1e2` 不会因为数值恰好是整数
/// 就被当成 `Int`：有没有小数点／指数决定形状。
///
/// `repr` 缺失只可能来自手工构造的 `Json`。拿不到原文时一律按浮点处理：
/// 宁可让整数读取报类型不符，也不能把浮点静默当成整数。
fn json_to_value(json : Json) -> @config.Value raise @config.ConfigError {
  match json {
    Json::Null => @config.Value::null()
    Json::True => @config.Value::bool(true)
    Json::False => @config.Value::bool(false)
    Json::Number(n, repr~) =>
      match repr {
        Some(literal) =>
          // 整数形状按 Int64 精确解析（大整数不丢）；浮点形状直接保留 Double
          if is_integer_literal(literal) {
            @config.Value::int(int64_of(literal))
          } else {
            @config.Value::float(n)
          }
        None => @config.Value::float(n)
      }
    Json::String(s) => @config.Value::str(s)
    Json::Array(arr) => @config.Value::array(arr.map(json_to_value))
    Json::Object(obj) => {
      let table = Map([], capacity=obj.capacity())
      for k, v in obj {
        table[k] = json_to_value(v)
      }
      @config.Value::table(table)
    }
  }
}

///|
/// 字面量是不是整数形式。
///
/// JSON 的数字字面量只有两种非整数的写法：带小数点，或者带 `e` / `E` 指数。
/// `int64_of` 只接受整数形式，否则 `@bigint` 会 `abort` 整个进程
/// 而不是抛错——那种失败方式对一个配置库来说是不能接受的。
fn is_integer_literal(literal : String) -> Bool {
  !literal.contains(".") && !literal.contains("e") && !literal.contains("E")
}

///|
/// 按 `Int64` 精确解析一个字面量。
///
/// 调用前必须先用 `is_integer_literal` 过一遍。
/// 真的塞不进 `Int64` 的整数直接报错，不做静默截断。
fn int64_of(literal : String) -> Int64 raise @config.ConfigError {
  let big = @bigint.BigInt::from_string(literal)
  if big.compare_int64(9223372036854775807L) > 0 ||
    big.compare_int64(-9223372036854775808L) < 0 {
    raise @config.ConfigError::ParseError(
      "整数 \{literal} 超出 Int64 范围",
    )
  }
  big.to_int64()
}

///|
/// `Value` → `Json`。
///
/// 注意这是自由函数不是方法：MoonBit 不允许给别的包定义的类型加方法
/// （`4059: Cannot define method for foreign type`），所以核心里的
/// `Value::to_json` 在拆分时只能降级成这样。
///
/// `Int` 走 `Json::number`，同时把原文塞进 `repr`：`FromJson for Int` 这类
/// 只认数字的字段能取到值，`repr` 又让超出 `Double` 精确范围的整数不丢精度
/// （`Json::stringify` 用的也是 `repr`）。代价是 `FromJson for Int64` 仍只吃
/// 字符串，结构体里的 64 位字段要写 `Int64Text`，见 `extract.mbt`。
///
/// `Bytes` 走 core 的 `ToJson for Bytes`：可打印 ASCII 直通，其余写成
/// `\xHH`，和 `FromJson for Bytes` 读的是同一套格式，两头对称。
pub fn to_json(v : @config.Value) -> Json {
  to_json_with_float_mode(v, false)
}

///|
/// 内部转换：`float_probe` 为真时，所有浮点都写成 JSON 字符串 `"NaN"`。
///
/// 这是提取阶段用来识别「浮点落进整数字段」的探针：标准库的
/// `Double::from_json` / `Float::from_json` 接受字符串 `"NaN"`，而
/// `Int::from_json` / `UInt::from_json` 只接受数字，会拒绝它。
/// 普通 `to_json` 不受影响。
fn to_json_with_float_mode(v : @config.Value, float_probe : Bool) -> Json {
  match v.kind {
    @config.ValueKind::Null => Json::null()
    @config.ValueKind::Bool(b) => Json::boolean(b)
    @config.ValueKind::Int(i) => Json::number(i.to_double(), repr=i.to_string())
    @config.ValueKind::Float(f) =>
      if float_probe {
        Json::string("NaN")
      } else {
        Json::number(f)
      }
    @config.ValueKind::Str(s) => Json::string(s)
    @config.ValueKind::Bytes(b) => @json.to_json(b)
    @config.ValueKind::Array(arr) =>
      Json::array(arr.map(fn(x) { to_json_with_float_mode(x, float_probe) }))
    @config.ValueKind::Table(t) => {
      let obj = Map([], capacity=t.capacity())
      for k, x in t {
        obj[k] = to_json_with_float_mode(x, float_probe)
      }
      Json::object(obj)
    }
  }
}

///|
/// 提取阶段的浮点探针树，见 `to_json_with_float_mode`。
fn to_probe_json(v : @config.Value) -> Json {
  to_json_with_float_mode(v, true)
}

// extract / extract_from 在 extract.mbt：那里还要处理 64 位包装类型和错误翻译
