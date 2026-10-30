///|
/// moonfig 示例：配置校验
///
/// 运行：`moon run examples/validate`
///
/// 场景：服务 `orders` 的配置写错了——端口越界、日志级别拼错、还多了一个键。
/// 校验放在启动阶段，问题一次暴露，不用等业务代码跑到一半才发现。
///
/// 两条路，共用同一套规则和错误类型：
///
/// 1. 按键取值：没有结构体声明，规则显式列出路径和约束。
/// 2. 提取到结构体：约束写在 `Validate` 实现里，提取后立刻跑。

///|
using @config {
  type Config,
  type MemorySource,
  type Rule,
  type Value,
  type ValueKind,
}

///|
using @jsonfmt {extract_validated_from}

///|
/// 故意写坏的配置：端口越界、用户名空、日志级别拼错、多了一个 `extra`
fn build_config() -> Config raise {
  Config::new()
  .add(
    MemorySource::new(
      Value::table({
        "db": Value::table({
          "host": Value::str("localhost"),
          "port": Value::int(70000L),
          "user": Value::str(""),
          "extra": Value::bool(true),
        }),
        "log": Value::table({ "level": Value::str("verbose") }),
      }),
    ),
  )
  .build()
}

///|
/// 按键校验的规则表：路径、约束、失败时怎么描述，都写在一处
fn db_rules() -> Array[Rule] {
  [
    Rule::int_range("db.port", 1L, 65535L),
    Rule::string_len("db.user", 1, 64),
    Rule::one_of("log.level", ["debug", "info", "warn", "error"]),
    Rule::allowed_keys("db", ["host", "port", "user"]),
  ]
}

///|
/// 第一种用法：按键校验，遇到第一个错误就停
///
/// 和 `get_*` 一样，先报错先停；要一次列全用 `validate_all`。
fn validate_by_key(cfg : Config) -> Unit raise {
  cfg.validate(db_rules())
}

///|
/// 第二种用法：一次列出全部问题
fn show_all_errors(cfg : Config) -> Unit raise {
  let errors = cfg.validate_all(db_rules())
  if errors.is_empty() {
    println("passed")
  } else {
    for error in errors {
      println(error.to_string())
    }
  }
}

///|
/// 结构体：字段和配置一一对应
struct DbCfg {
  host : String
  port : Int32
  user : String
} derive(@json.FromJson)

///|
pub extend DbCfg with @json.FromJson::{from_json}

///|
/// 约束写在结构体旁边：字段改了，约束跟着改
///
/// `prefix` 是提取时的起始路径（这里是 `db`），拼上字段名就是完整的键路径，
/// 报错时和按键校验给出同样的消息。
impl @config.Validate for DbCfg with fn validate(
  self : DbCfg,
  prefix : @config.KeyPath,
) -> Unit raise @config.ConfigError {
  @config.check_int_range(prefix.add("port"), self.port.to_int64(), 1L, 65535L)
  @config.check_string_len(prefix.add("user"), self.user, 1, 64)
}

///|
/// 第三种用法：先提取成结构体，再跑结构体自己的约束
///
/// 未知键不在这条路上：`derive(FromJson)` 会忽略结构体里没有的字段，
/// 它不知道自己外面多了什么。未知键只能按键查，见 `db_rules` 里的 `allowed_keys`。
fn validate_by_struct(cfg : Config) -> Unit raise {
  let db : DbCfg = extract_validated_from(cfg, "db")
  println("db.host = \{db.host}")
}

///|
/// 内置规则不够用时自己写：返回 `None` 表示通过，`Some(实际值)` 表示失败
///
/// `实际值` 会进错误消息，密码这类字段别原样返回，只写长度或类型。
fn validate_host(cfg : Config) -> Unit raise {
  cfg.validate([
    Rule::custom("db.host", "non-empty and without spaces", fn(value) {
      match value.kind {
        ValueKind::Str(text) =>
          if text.length() > 0 && !text.contains(" ") {
            None
          } else {
            Some(text)
          }
        _ => Some(value.kind.name())
      }
    }),
  ])
}

///|
fn main raise {
  let cfg = build_config()

  println("== 1. Validate by key: stop at the first error ==")
  try {
    validate_by_key(cfg)
    println("passed")
  } catch {
    error => println(error.to_string())
  }

  println("")
  println("== 2. Validate by key: list every error ==")
  show_all_errors(cfg)

  println("")
  println("== 3. Extract into a struct: constraints follow the fields ==")
  validate_by_struct(cfg) catch {
    error => println(error.to_string())
  }

  println("")
  println("== 4. Custom rules ==")
  try {
    validate_host(cfg)
    println("passed")
  } catch {
    error => println(error.to_string())
  }
}
