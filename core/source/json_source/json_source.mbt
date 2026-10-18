///|
/// JSON 来源：文本 → `Value`，用 core 的 `@json`，零第三方依赖。
pub struct JsonSource {
  text : String
}

///|
/// 从 JSON 文本构造
pub fn JsonSource::from_str(text : String) -> JsonSource {
  JsonSource::{ text, }
}

///|
pub impl @config.Source for JsonSource with fn collect(self : JsonSource) -> @config.Value raise @config.ConfigError {
  let json = @json.parse(self.text) catch {
    e => raise @config.ConfigError::ParseError(e.to_string())
  }
  json_to_value(json)
}

///|
pub extend JsonSource with @config.Source::{collect}

///|
/// `Json` → `Value`：数字分成 `Int` / `Float`，整数一律 `Int64`。
///
/// core 的 `Json::Number` 带一个 `repr` 字段，**只在字面量超出 `Double`
/// 的精确整数范围（> 2^53 - 1）时**才留着原文，常见情况是 `None`。
/// 所以这里分两条路：
///
/// - `repr` 有值 → 原文在手，能精确解析
/// - `repr` 是 `None` → 原文已经拿不回来，只能看值本身：整数值当整数
fn json_to_value(json : Json) -> @config.Value raise @config.ConfigError {
  match json {
    Json::Null => @config.Value::null()
    Json::True => @config.Value::bool(true)
    Json::False => @config.Value::bool(false)
    Json::Number(n, repr~) =>
      match repr {
        Some(literal) =>
          // 两条路都会填 repr，必须分开处理：
          // 整数超范围 → 按 Int64 精确解析；浮点超范围 → n 已是 ±infinity 哨兵
          if is_integer_literal(literal) {
            @config.Value::int(int64_of(literal))
          } else {
            @config.Value::float(n)
          }
        None =>
          if is_int64(n) {
            @config.Value::int(n.to_int64())
          } else {
            @config.Value::float(n)
          }
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
/// 整数值、且塞得进 `Int64` 才算整数。
///
/// 已知取舍：原文没了，`1.0`、`1e2` 这种写了小数点／指数的整数值也按整数算。
/// 反过来不会错——`5432` 一定是整数，不然 `get_int` 全都取不到。
fn is_int64(n : Double) -> Bool {
  !n.is_nan() &&
  n == n.trunc() &&
  n >= -9223372036854775808.0 &&
  n < 9223372036854775808.0
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
/// `Int` 走 `Json::string`：core 自己就把 `Int64` 序列化成字符串，
/// 且 `FromJson for Int64` 只吃字符串，两头对称才不丢大整数。
pub fn to_json(v : @config.Value) -> Json {
  match v.kind {
    @config.ValueKind::Null => Json::null()
    @config.ValueKind::Bool(b) => Json::boolean(b)
    @config.ValueKind::Int(i) => Json::string(i.to_string())
    @config.ValueKind::Float(f) => Json::number(f)
    @config.ValueKind::Str(s) => Json::string(s)
    @config.ValueKind::Array(arr) => Json::array(arr.map(fn(x) { to_json(x) }))
    @config.ValueKind::Table(t) => {
      let obj = Map([], capacity=t.capacity())
      for k, x in t {
        obj[k] = to_json(x)
      }
      Json::object(obj)
    }
  }
}

///|
/// 提取到结构体：`Value` → `Json` → `FromJson`。
///
/// 用户的类型用编译器自带的 `derive(FromJson)`，库不生成任何代码。
pub fn[T : @json.FromJson] extract(
  v : @config.Value,
) -> T raise @config.ConfigError {
  @json.from_json(to_json(v)) catch {
    e =>
      raise @config.ConfigError::ParseError("提取到结构体失败：\{e}")
  }
}

///|
/// 取配置里某个路径的值并提取成用户结构体。
///
/// 原来是 `Config::extract`，拆分时降级成自由函数——理由同 `to_json`。
pub fn[T : @json.FromJson] extract_from(
  cfg : @config.Config,
  path : String,
) -> T raise @config.ConfigError {
  extract(cfg.get_value(path))
}
