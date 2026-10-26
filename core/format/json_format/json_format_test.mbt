// Blackbox tests for the json package, against its public API.

///|
using @config {
  type StringSource,
  type Config,
  type ConfigError,
  type MemorySource,
  type Value,
}

///|
using @json_format {
  type JsonFormat,
  extract,
  extract_from,
  extract_validated_from,
}

///|
/// 测试里省掉重复的 `StringSource::new(..., JsonFormat::new())`
fn json(text : String) -> StringSource {
  StringSource::new(text, JsonFormat::new())
}

///|
/// 用户自己的类型只要 `derive(FromJson)`，库不生成任何代码
struct DbCfg {
  host : String
  port : Int32
} derive(@json.FromJson)

///|
pub extend DbCfg with @json.FromJson::{from_json}

///|
/// 结构体自己的约束：端口必须落在合法范围内
impl @config.Validate for DbCfg with fn validate(
  self : DbCfg,
  prefix : @config.KeyPath,
) -> Unit raise @config.ConfigError {
  @config.check_int_range(prefix.add("port"), self.port.to_int64(), 1L, 65535L)
}

///|
/// 64 位字段写 `Int64Text`：core 的 `Int64` 只吃 JSON 字符串，和本库的整数映射对不上
struct BigCfg {
  id : @json_format.Int64Text
} derive(@json.FromJson)

///|
pub extend BigCfg with @json.FromJson::{from_json}

///|
/// 只用来验证「直接写 Int64」时的报错，不参与别的测试
#warnings("-unused_field")
struct LegacyCfg {
  id : Int64
} derive(@json.FromJson)

///|
pub extend LegacyCfg with @json.FromJson::{from_json}

///|
/// 浮点字段仍然要能正常提取；浮点探针不能把 `Double` 也拦掉
struct RatioCfg {
  ratio : Double
} derive(@json.FromJson)

///|
pub extend RatioCfg with @json.FromJson::{from_json}

///|
/// 整数值取 `Int`，带小数的取 `Float`
test "json source splits int and float" {
  let cfg = Config::new()
    .add(
      json(
        "{\"api\": {\"url\": \"https://x.com\", \"timeout\": 30, \"ratio\": 1.5}}",
      ),
    )
    .build()
  assert_eq(cfg.get_string("api.url"), "https://x.com")
  assert_eq(cfg.get_int("api.timeout"), 30L)
  assert_eq(cfg.get_float("api.ratio"), 1.5)
}

///|
/// `1.0` 这种整数值的浮点写法仍然按 Float 存，`get_int` 不能把它当整数。
test "integral float is not readable as Int" {
  let cfg = Config::new().add(json("{\"port\": 1.0}")).build()
  let message = try {
    ignore(cfg.get_int("port"))
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(message, "配置项 port 类型不符：期望 Int，实际 Float")
  assert_eq(cfg.get_float("port"), 1.0)
}

///|
/// 坏文本报 ParseError，别崩
test "bad json raises ParseError" {
  let failed = try {
    // 解析发生在 build() 里，来源是坏的就要在这一步报出来
    let cfg = Config::new().add(json("{oops")).build()
    ignore(cfg.get_value("anything"))
    false
  } catch {
    ConfigError::ParseError(_) => true
    _ => false
  }
  assert_true(failed)
}

///|
/// 大整数端到端不丢：9007199254740993 超出 Double 精度
test "big int keeps full precision" {
  let cfg = Config::new().add(json("{\"id\": 9007199254740993}")).build()
  assert_eq(cfg.get_int("id"), 9007199254740993L)
}

///|
/// 提取到用户结构体
test "extract into user struct" {
  let cfg = Config::new()
    .add(json("{\"db\": {\"host\": \"localhost\", \"port\": 5432}}"))
    .build()
  let db : DbCfg = extract_from(cfg, "db")
  assert_eq(db.host, "localhost")
  assert_eq(db.port, 5432)
}

///|
/// 结构体里的 64 位字段用 `Int64Text`，超出 Double 精度也不丢
test "extract keeps 64-bit field exact" {
  let cfg = Config::new()
    .add(json("{\"db\": {\"id\": 9007199254740993}}"))
    .build()
  let big : BigCfg = extract_from(cfg, "db")
  assert_eq(big.id.to_int64(), 9007199254740993L)
}

///|
/// 结构体里直接写 Int64：报错并给出改法
test "extract explains Int64 fields" {
  let cfg = Config::new().add(json("{\"db\": {\"id\": 5432}}")).build()
  let message = try {
    let legacy : LegacyCfg = extract_from(cfg, "db")
    ignore(legacy)
    ""
  } catch {
    error => error.to_string()
  }
  assert_eq(
    message, "解析失败：配置项 db.id 是 64 位整数：结构体字段请声明为 Int64Text，或改用 get_int",
  )
}

///|
/// 64 位字段也不接受字符串来源：严格类型不做隐式转换
test "Int64Text rejects string source" {
  let cfg = Config::new().add(json("{\"db\": {\"id\": \"5432\"}}")).build()
  let message = try {
    let big : BigCfg = extract_from(cfg, "db")
    ignore(big)
    ""
  } catch {
    error => error.to_string()
  }
  assert_eq(message, "配置项 db.id 类型不符：期望 Int64，实际 Str")
}

///|
/// 提取失败也报键名、期望类型、实际类型
test "extract reports key and types" {
  let cfg = Config::new()
    .add(json("{\"db\": {\"host\": \"localhost\", \"port\": \"5432\"}}"))
    .build()
  let message = try {
    let db : DbCfg = extract_from(cfg, "db")
    ignore(db)
    ""
  } catch {
    error => error.to_string()
  }
  assert_eq(message, "配置项 db.port 类型不符：期望 Int，实际 Str")
}

///|
/// 浮点提取成 `Int` 不能截断：标准库的 `Int::from_json` 会直接 `to_int()`，
/// 库里的 `"NaN"` 探针负责把它拦下来。
test "extract rejects float into Int field" {
  let cfg = Config::new()
    .add(json("{\"db\": {\"host\": \"localhost\", \"port\": 5432.7}}"))
    .build()
  let message = try {
    let db : DbCfg = extract_from(cfg, "db")
    ignore(db)
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    message, "配置项 db.port 类型不符：期望 Int，实际 Float",
  )
}

///|
/// 同一棵树里的 `Double` 字段不受浮点探针影响，原值照常取回。
test "extract keeps fractional Double field" {
  let cfg = Config::new().add(json("{\"ratio\": 1.25}")).build()
  let ratio : RatioCfg = extract_from(cfg, "")
  assert_eq(ratio.ratio, 1.25)
}

///|
/// 提取也可以先拿原始值再走 `extract`
test "extract from raw value" {
  let cfg = Config::new()
    .add(json("{\"db\": {\"host\": \"localhost\", \"port\": 5432}}"))
    .build()
  let db : DbCfg = extract(cfg.get_value("db"))
  assert_eq(db.host, "localhost")
}

///|
/// JSON 来源和内存来源可以混着叠，后者赢
///
/// 这是核心 `Config` 不认识任何格式的最好证明：两个来源分属两个包，
/// 却能进同一个 `Config`。
test "json and memory sources combine" {
  let cfg = Config::new()
    .add(json("{\"db\": {\"host\": \"localhost\", \"port\": 5432}}"))
    .add(
      MemorySource::new(
        Value::table({ "db": Value::table({ "port": Value::int(6543L) }) }),
      ),
    )
    .build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 6543L)
}

///|
/// 提取后立刻跑结构体自己的 `Validate`，路径拼上提取时的前缀
test "extract_validated_from reports the constraint" {
  let cfg = Config::new()
    .add(json("{\"db\": {\"host\": \"localhost\", \"port\": 70000}}"))
    .build()
  let message = try {
    let _ : DbCfg = extract_validated_from(cfg, "db")
    "没有报错"
  } catch {
    error => error.to_string()
  }
  assert_eq(
    message, "配置项 db.port 不符合约束：期望 1..65535，实际 70000",
  )
}

///|
/// 符合约束时原样返回提取结果
test "extract_validated_from returns the struct" {
  let cfg = Config::new()
    .add(json("{\"db\": {\"host\": \"localhost\", \"port\": 5432}}"))
    .build()
  let db : DbCfg = extract_validated_from(cfg, "db")
  assert_eq(db.host, "localhost")
  assert_eq(db.port, 5432)
}
