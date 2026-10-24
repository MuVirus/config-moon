///|
/// moonfig 示例：四层来源叠在一起，最后还能问出每个值来自哪一层。
///
/// 运行：`moon run examples/multi_source -- --log-level=debug`
///
/// 四层来源，按加入顺序（后加的赢）：
///
/// 1. 内存默认值
/// 2. 配置文件 `examples/multi_source/config/app.json`
/// 3. 环境变量 `APP_DB_PORT` / `APP_DB_PASSWORD`
/// 4. 命令行参数 `--log-level=debug`
///
/// 环境变量这一层为了演示可复现，由程序自己设上；真实程序直接用进程里已有的
/// 环境变量，不需要这一段。

///|
using @config {type Config, type MemorySource, type Origin, type Value}

///|
using @jsonfmt {type JsonFormat}

///|
using @file_source {type FileSource}

///|
using @env_source {type EnvSource}

///|
using @cli_source {type CliSource}

///|
/// 演示用的环境变量：真实程序不用这一层
fn seed_env() -> Unit {
  @env.set_env_var("APP_DB_PORT", "6543")
  @env.set_env_var("APP_DB_PASSWORD", "s3cret")
}

///|
/// 演示结束后清掉，免得污染 shell
fn clear_env() -> Unit {
  @env.unset_env_var("APP_DB_PORT")
  @env.unset_env_var("APP_DB_PASSWORD")
}

///|
/// 组装四层来源
fn build_config() -> Config raise {
  let defaults = MemorySource::new(
    Value::table({
      "db": Value::table({
        "host": Value::str("localhost"),
        "port": Value::int(5432L),
      }),
      "log": Value::table({ "level": Value::str("info") }),
      "feature": Value::table({ "debug": Value::bool(false) }),
    }),
  )
  Config::new()
  .add(defaults)
  .add(
    FileSource::new("examples/multi_source/config/app.json", JsonFormat::new()),
  )
  .add(EnvSource::new("APP_"))
  .add(CliSource::new())
  .build()
}

///|
fn show(origin : Origin?) -> String {
  match origin {
    Some(origin) => "\{origin.label}"
    None => "（没有来源）"
  }
}

///|
fn main raise {
  seed_env()
  let cfg = build_config()

  println("== 生效的值 ==")
  println("db.host    = \{cfg.get_string("db.host")}")
  println("db.port    = \{cfg.get_int("db.port")}")
  println("db.password= \{cfg.get_string("db.password")}")
  println("log.level  = \{cfg.get_string("log.level")}")
  println("feature.debug = \{cfg.get_bool("feature.debug")}")

  println("")
  println("== 每个值来自哪一层 ==")
  println("db.host       <- \{show(cfg.origin_of("db.host"))}")
  println("db.port       <- \{show(cfg.origin_of("db.port"))}")
  println("db.password   <- \{show(cfg.origin_of("db.password"))}")
  println("log.level     <- \{show(cfg.origin_of("log.level"))}")
  println("feature.debug <- \{show(cfg.origin_of("feature.debug"))}")

  println("")
  println("== --print-config 会列出什么 ==")
  let origins = cfg.origins()
  for pair in origins {
    println("\{pair.0}  \{pair.1.label}")
  }

  clear_env()
}
