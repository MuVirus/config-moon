///|
/// 环境变量来源：把进程环境变量读成一棵树。
///
/// **前缀决定读谁。** 只有以 `prefix` 开头的变量会被读进来，其余忽略；
/// 前缀本身不参与键名。`EnvSource::new("APP_")` 读 `APP_DB_PORT`，
/// 键是 `db.port`；`EnvSource::all()` 读全部变量。
///
/// **下划线和点都算层级。** `APP_DB_PORT` → `db.port`，`APP_DB.PORT` 也一样。
/// 键名统一转小写，因为环境变量习惯全大写，而路径习惯小写。
///
/// **值按字面猜类型。** `"true"` / `"false"` 是布尔，整数按 `Int64` 解析
/// （超出范围报错），带小数点或指数的是浮点，其余是字符串。空值是空字符串。
///
/// **冲突报错，不猜谁该赢。** `APP_DB=1` 和 `APP_DB_PORT=2` 同时存在时，
/// `db` 已经是整数，没法再放 `db.port`，报 `ParseError` 并点名两个变量；
/// 两个变量只差大小写时同样报错。
///
/// 每个叶子都自带 `Origin`：`kind` 是 `Env`，标签是 `env:APP_DB_PORT`，
/// 所以 `origin_of("db.port")` 能指出具体是哪个变量。
pub struct EnvSource {
  prefix : String
}

///|
/// 读以 `prefix` 开头的环境变量
///
/// Example:
///
/// ```mbt check
/// test {
///   @env.set_env_var("MOONFIG_DEMO_PORT", "6543")
///   let cfg = @config.Config::new()
///     .add(@env_source.EnvSource::new("MOONFIG_DEMO_"))
///     .build()
///   assert_eq(cfg.get_int("port"), 6543L)
///   @env.unset_env_var("MOONFIG_DEMO_PORT")
/// }
/// ```
pub fn EnvSource::new(prefix : String) -> EnvSource {
  { prefix, }
}

///|
/// 读全部环境变量
pub fn EnvSource::all() -> EnvSource {
  { prefix: "", }
}

///|
pub impl @config.Source for EnvSource with fn collect(self : EnvSource) -> @config.Value raise @config.ConfigError {
  let vars = @env.get_env_vars()
  let names : Array[String] = []
  for name, _ in vars {
    if name.has_prefix(self.prefix) {
      let key = name.strip_prefix(self.prefix).unwrap()
      // 前缀自己（`APP_`）不构成一个键
      if key.length() > 0 {
        names.push(name)
      }
    }
  }
  // 排序让结果和 Map 的遍历顺序无关
  names.sort()
  let root : Map[String, @config.Value] = Map([])
  let seen : Map[String, String] = Map([])
  for name in names {
    let key = name.strip_prefix(self.prefix).unwrap()
    let path = key_path(key, name)
    let raw = vars.get(name).unwrap()
    let value = @config.Value::from_literal(raw) catch {
      @config.ConfigError::ParseError(message) =>
        raise @config.ConfigError::ParseError(
          "环境变量 \{name}：\{message}",
        )
      error => raise error
    }
    let origin = @config.Origin::{
      kind: @config.SourceKind::Env,
      label: "env:\{name}",
      locator: None,
    }
    assign(root, seen, path, name, value.with_origin(origin))
  }
  @config.Value::table(root)
}

///|
/// 整层来源报 `Env`；叶子有自己的标签，这里只是兜底
pub impl @config.Source for EnvSource with fn origin(self : EnvSource) -> @config.Origin? {
  Some(@config.Origin::{
    kind: @config.SourceKind::Env,
    label: "env:\{self.prefix}*",
    locator: None,
  })
}

///|
pub extend EnvSource with @config.Source::{collect, origin}

///|
/// 变量名 → 层级路径：去掉前缀后按 `_` 和 `.` 拆层，统一转小写。
fn key_path(
  key : StringView,
  name : String,
) -> Array[String] raise @config.ConfigError {
  let path : Array[String] = []
  let segment = StringBuilder()
  for c in key {
    if c == '_' || c == '.' {
      push_segment(path, segment, name)
    } else {
      segment.write_char(c.to_ascii_lowercase())
    }
  }
  push_segment(path, segment, name)
  path
}

///|
/// 一段键名收进路径；空的层说明变量名写坏了
fn push_segment(
  path : Array[String],
  segment : StringBuilder,
  name : String,
) -> Unit raise @config.ConfigError {
  let text = segment.to_string()
  if text.length() == 0 {
    raise @config.ConfigError::ParseError(
      "环境变量 \{name}：键名有空的层级",
    )
  }
  path.push(text)
  segment.reset()
}

///|
/// 顺着层级路径写入，中间缺的层顺手建出来。
/// 路径被标量占了就报错，并点名写出这个键的变量。
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
              "环境变量 \{name}：\{joined} 已经是 \{k.name()}（由 \{owner} 提供），不能当层级名",
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
  match seen.get(joined) {
    Some(other) =>
      if other != name {
        raise @config.ConfigError::ParseError(
          "环境变量 \{name} 和 \{other} 都指向 \{joined}",
        )
      }
    None => ()
  }
  seen[joined] = name
  cur[leaf] = value
}
