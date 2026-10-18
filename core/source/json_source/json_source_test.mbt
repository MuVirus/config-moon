// Blackbox tests for the json package, against its public API.

///|
using @config {type Config, type ConfigError, type MemorySource, type Value}

///|
using @json_source {type JsonSource, extract, extract_from}

///|
/// 用户自己的类型只要 `derive(FromJson)`，库不生成任何代码
struct DbCfg {
  host : String
  port : Int64
} derive(@json.FromJson)

///|
pub extend DbCfg with @json.FromJson::{from_json}

///|
/// 整数值取 `Int`，带小数的取 `Float`
test "json source splits int and float" {
  let cfg = Config::new()
    .add(
      JsonSource::from_str(
        "{\"api\": {\"url\": \"https://x.com\", \"timeout\": 30, \"ratio\": 1.5}}",
      ),
    )
    .build()
  assert_eq(cfg.get_string("api.url"), "https://x.com")
  assert_eq(cfg.get_int("api.timeout"), 30L)
  assert_eq(cfg.get_float("api.ratio"), 1.5)
}

///|
/// 坏文本报 ParseError，别崩
test "bad json raises ParseError" {
  let failed = try {
    // 解析发生在 build() 里，来源是坏的就要在这一步报出来
    let cfg = Config::new().add(JsonSource::from_str("{oops")).build()
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
  let cfg = Config::new()
    .add(JsonSource::from_str("{\"id\": 9007199254740993}"))
    .build()
  assert_eq(cfg.get_int("id"), 9007199254740993L)
}

///|
/// 提取到用户结构体
test "extract into user struct" {
  let cfg = Config::new()
    .add(
      JsonSource::from_str(
        "{\"db\": {\"host\": \"localhost\", \"port\": 5432}}",
      ),
    )
    .build()
  let db : DbCfg = extract_from(cfg, "db")
  assert_eq(db.host, "localhost")
  assert_eq(db.port, 5432L)
}

///|
/// 提取也可以先拿原始值再走 `extract`
test "extract from raw value" {
  let cfg = Config::new()
    .add(
      JsonSource::from_str(
        "{\"db\": {\"host\": \"localhost\", \"port\": 5432}}",
      ),
    )
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
    .add(
      JsonSource::from_str(
        "{\"db\": {\"host\": \"localhost\", \"port\": 5432}}",
      ),
    )
    .add(
      MemorySource::new(
        Value::table({ "db": Value::table({ "port": Value::int(6543L) }) }),
      ),
    )
    .build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 6543L)
}
