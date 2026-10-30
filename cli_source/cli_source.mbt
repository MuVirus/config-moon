///|
/// 命令行来源：把 `--key=value` 形式的参数读成一棵树。
///
/// **只认长选项。** `--key=value` 给值，`--flag` 表示布尔 `true`，
/// `--no-flag` 表示布尔 `false`。不认识的参数（位置参数、`-x` 短选项）一律忽略：
/// 命令行上还有程序自己的参数，不能因为看不懂就报错。
///
/// **`--` 之后全是位置参数**，不再当配置读。
///
/// **下划线和点都算层级。** `--log-level=debug` → `log.level`；
/// `--db.port=6543` 也一样。键名统一转小写。
///
/// **值按字面猜类型**，规则和环境变量相同：`"true"` / `"false"` 是布尔，
/// 整数按 `Int64` 解析（超出范围报错），带小数点或指数的是浮点，其余是字符串。
///
/// **同一个键写两次，后写的赢。** 但标量和层级互相挡路时（`--a=1 --a.b=2`、
/// `--a.b=1 --a=2`）报 `ParseError`，不静默丢掉前一个值。
///
/// 整层共用一个 site：`describe` 按路径查回原始参数名，标签是不带值的写法
/// （`cli:--log-level`），密码不会漏进日志。
pub struct CliSource {
  args : Array[String]
}

///|
/// 命令行层的 site：保留「路径 → 原始参数名」的索引。
///
/// 参数名去掉 `=value` 才存进来；`describe` 时才拼成 `cli:--log-level`。
priv struct CliSite {
  names : Map[String, String]
}

///|
impl @config.OriginSite for CliSite with fn kind(_ : CliSite) -> @config.SourceKind {
  @config.SourceKind::Cli
}

///|
impl @config.OriginSite for CliSite with fn describe(
  self : CliSite,
  path : @config.KeyPath,
) -> String {
  match self.names.get(path.to_string()) {
    Some(arg) => "cli:\{arg}"
    None => "cli:args"
  }
}

///|
/// 读进程自己的命令行参数（`@env.args()` 里的可执行文件名会按「不认识的参数」忽略）
///
/// Example:
///
/// ```mbt check
/// test {
///   let args : Array[String] = ["app", "--db.port=6543", "--debug"]
///   let cfg = @config.Config::new()
///     .add(@cli_source.CliSource::from_args(args))
///     .build()
///   assert_eq(cfg.get_int("db.port"), 6543L)
///   assert_true(cfg.get_bool("debug"))
/// }
/// ```
pub fn CliSource::new() -> CliSource {
  { args: @env.args(), }
}

///|
/// 用给定的参数表构造，方便测试和自定义解析结果
pub fn CliSource::from_args(args : Array[String]) -> CliSource {
  { args, }
}

///|
pub impl @config.Source for CliSource with fn collect(self : CliSource) -> @config.Layer raise @config.ConfigError {
  let root : Map[String, @config.Value] = Map([])
  let seen : Map[String, String] = Map([])
  for arg in self.args {
    if arg == "--" {
      break
    }
    let rest = match arg.strip_prefix("--") {
      Some(rest) => rest
      None => continue
    }
    if rest.length() == 0 {
      continue
    }
    let split = rest.split_once("=")
    let key = match split {
      Some(pair) => pair.0
      None => rest
    }
    // 标签只留参数名，不带值
    let name = "--\{key}"
    let path = match split {
      Some(_) => key_path(key)
      None =>
        match key.strip_prefix("no-") {
          Some(inner) => key_path(inner)
          None => key_path(key)
        }
    }
    let value = match split {
      Some(pair) =>
        @config.Value::from_literal(pair.1) catch {
          @config.ConfigError::ParseError(message) =>
            raise @config.ConfigError::ParseError(
              "argument cli:\{name}: \{message}",
            )
          error => raise error
        }
      None =>
        match key.strip_prefix("no-") {
          Some(_) => @config.Value::bool(false)
          None => @config.Value::bool(true)
        }
    }
    assign(root, seen, path, name, value)
  }
  @config.Layer::new(
    @config.Value::table(root),
    Some(CliSite::{ names: seen, } as &@config.OriginSite),
  )
}

///|
pub impl @config.Source for CliSource with fn kind(_ : CliSource) -> @config.SourceKind {
  @config.SourceKind::Cli
}

///|
pub extend CliSource with @config.Source::{collect, kind, raw_locator}

///|
/// 参数名 → 层级路径：按 `-` 和 `.` 拆层，统一转小写。
fn key_path(key : StringView) -> Array[String] raise @config.ConfigError {
  let path : Array[String] = []
  let segment = StringBuilder()
  for c in key {
    if c == '-' || c == '.' {
      push_segment(path, segment, key)
    } else {
      segment.write_char(c.to_ascii_lowercase())
    }
  }
  push_segment(path, segment, key)
  path
}

///|
fn push_segment(
  path : Array[String],
  segment : StringBuilder,
  key : StringView,
) -> Unit raise @config.ConfigError {
  let text = segment.to_string()
  if text.length() == 0 {
    raise @config.ConfigError::ParseError(
      "argument --\{key}: key has an empty segment",
    )
  }
  path.push(text)
  segment.reset()
}

///|
/// 顺着层级路径写入，中间缺的层顺手建出来。
fn assign(
  root : Map[String, @config.Value],
  seen : Map[String, String],
  path : Array[String],
  name : String,
  value : @config.Value,
) -> Unit raise @config.ConfigError {
  let mut cur = root
  let mut joined = ""
  let mut i = 0
  while i < path.length() - 1 {
    let seg = path[i]
    joined = if joined == "" { seg } else { "\{joined}.\{seg}" }
    let next = match cur.get(seg) {
      Some(existing) =>
        match existing.kind {
          @config.ValueKind::Table(table) => table
          k => {
            let owner = seen.get(joined).unwrap_or("?")
            raise @config.ConfigError::ParseError(
              "argument cli:\{name}: \{joined} is already \{k.name()} (provided by cli:\{owner}) and cannot be used as a path segment",
            )
          }
        }
      None => {
        let table : Map[String, @config.Value] = Map([])
        cur[seg] = @config.Value::table(table)
        table
      }
    }
    cur = next
    i += 1
  }
  let leaf = path[path.length() - 1]
  joined = if joined == "" { leaf } else { "\{joined}.\{leaf}" }
  match cur.get(leaf) {
    Some(existing) =>
      match existing.kind {
        @config.ValueKind::Table(_) =>
          raise @config.ConfigError::ParseError(
            "argument cli:\{name}: \{joined} already has configuration below it and cannot be replaced wholesale",
          )
        _ => ()
      }
    None => ()
  }
  seen[joined] = name
  cur[leaf] = value
}
