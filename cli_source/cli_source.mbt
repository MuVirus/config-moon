///|
/// 命令行来源：把参数读成一棵树。
///
/// **取值风格只有一种。** 构造时选 `CliValueStyle::Equals`（默认）就只认
/// `--key=value` / `-p=value`；选 `CliValueStyle::Separate` 就只认
/// `--key value` / `-p value`。两种不会同时生效：`Equals` 下的 `--key value`
/// 只把 `--key` 当布尔开关，`Separate` 下的 `--key=value` 报 `ParseError`，
/// 不会悄悄改按另一种风格解释。
///
/// **布尔开关。** 裸 `--key` 是 `true`，`--no-key` 是 `false`；短开关要先
/// `with_short_flag` 登记，可以连写（`-vq` 等于 `-v -q`）。短开关不取值，
/// 要显式写 false 用 `--no-key`。
///
/// **短选项要先登记。** `with_short_option("p", "db.port")` 收值，写法跟
/// 当前风格一致；没登记的短选项一律忽略。
///
/// **重复参数收成数组，用 `with_array` 声明。** 声明过的路径写几次就收成数组
/// （`--tag=a --tag=b` → `["a", "b"]`），只写一次也是单元素数组；
/// 没声明过的重复键仍是后写的赢。
///
/// **`--` 之后全是位置参数**，没映射的位置参数和没登记的短选项一律忽略：
/// 命令行上还有程序自己的参数，不能因为看不懂就报错。
///
/// **`-` 和 `.` 都算层级。** `--log-level=debug` → `log.level`；
/// `--db.port=6543` 也一样。键名统一转小写。
///
/// **值按字面猜类型**，规则和环境变量相同：`"true"` / `"false"` 是布尔，
/// 整数按 `Int64` 解析（超出范围报错），带小数点或指数的是浮点，其余是字符串。
/// `Separate` 下以 `-` 开头的值（比如负数）会被当成下一个选项，要写这种值请换回
/// `Equals` 风格用 `--key=-1`；单独一个 `-` 仍可当值。
///
/// **标量和层级互相挡路时报 `ParseError`**（`--a=1 --a.b=2`、`--a.b=1 --a=2`），
/// 不静默丢掉前一个值；数组声明和层级撞车时同样报错。
///
/// **位置参数默认不进配置。** 要把子命令、文件路径这类参数也收进来，用
/// `with_positional(0, "command")` 按「非选项参数」的顺序映射：选项本身和它
/// 吃掉的值跳过，`--` 之后全部算位置参数。`new()` 不数可执行文件名；
/// `from_args` 默认把整张表都当参数，`program_name=true` 时跳过第 0 个。
/// 位置值同样按字面猜类型，标签是 `cli:argv[下标]`。
///
/// 整层共用一个 site：`describe` 按路径查回原始参数名（位置参数是 `argv[下标]`），
/// 标签是不带值的写法（`cli:--log-level`、`cli:-p`），密码不会漏进日志。
pub struct CliSource {
  args : Array[String]
  priv value_style : CliValueStyle
  priv shorts : Map[String, CliShort]
  priv arrays : Map[String, Unit]
  priv positionals : Map[Int32, String]
  priv program_name : Bool
}

///|
/// 长选项（以及短选项）的取值写法，一个来源只用一种。
pub(all) enum CliValueStyle {
  /// 值跟在 `=` 后面：`--key=value`、`-p=value`（默认）
  Equals
  /// 值是下一个参数：`--key value`、`-p value`
  Separate
} derive(Eq)

///|
pub extend CliValueStyle with Eq::{not_equal, equal}

///|
/// 一个登记过的短选项：落到哪个配置路径、收不收值。
priv struct CliShort {
  key : String
  takes_value : Bool
}

///|
/// 命令行层的 site：保留「路径 → 原始参数名」的索引。
///
/// 参数名去掉值才存进来；`describe` 时才拼成 `cli:--log-level`。
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
/// 读进程自己的命令行参数（`@env.args()` 里的可执行文件名不参与位置编号）
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
  CliSource::from_args(@env.args(), program_name=true)
}

///|
/// 用给定的参数表构造，方便测试和自定义解析结果
///
/// 默认是 `CliValueStyle::Equals`；要 `--key value` 用 `with_value_style`。
/// 默认不跳过第 0 个参数；如果这张表来自 `@env.args()`、开头是程序名，
/// 传 `program_name=true`，位置编号才不会把程序名算进去。
pub fn CliSource::from_args(
  args : Array[String],
  program_name~ : Bool = false,
) -> CliSource {
  {
    args,
    value_style: CliValueStyle::Equals,
    shorts: Map([]),
    arrays: Map([]),
    positionals: Map([]),
    program_name,
  }
}

///|
/// 选一种取值风格；风格对长选项和登记过的短选项同时生效
///
/// 另一种风格的写法会报错：`Separate` 下写 `--key=value`、`Equals` 下给
/// 登记过的短选项写 `-p value`，都直接报 `ParseError`，不会自动换一种解释。
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = @config.Config::new()
///     .add(
///       @cli_source.CliSource::from_args(["--db.port", "6543", "--debug"]).with_value_style(
///         @cli_source.CliValueStyle::Separate,
///       ),
///     )
///     .build()
///   assert_eq(cfg.get_int("db.port"), 6543L)
///   assert_true(cfg.get_bool("debug"))
/// }
/// ```
pub fn CliSource::with_value_style(
  self : CliSource,
  style : CliValueStyle,
) -> CliSource {
  {
    args: self.args,
    value_style: style,
    shorts: self.shorts,
    arrays: self.arrays,
    positionals: self.positionals,
    program_name: self.program_name,
  }
}

///|
/// 登记一个收值的短选项，写法跟着当前风格走
///
/// `short` 写一个字符即可，前导 `-` 可写可不写。
///
/// Example:
///
/// ```mbt check
/// test {
///   let source = @cli_source.CliSource::from_args(["-p=6543", "-p=6000"]).with_short_option(
///     "p", "db.port",
///   )
///   let cfg = @config.Config::new().add(source).build()
///   assert_eq(cfg.get_int("db.port"), 6000L)
/// }
/// ```
pub fn CliSource::with_short_option(
  self : CliSource,
  short : String,
  key : String,
) -> CliSource {
  self.shorts[short_name(short)] = { key, takes_value: true, }
  self
}

///|
/// 登记一个布尔短选项：`-v` 是 `true`，连写 `-vq` 也行
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = @config.Config::new()
///     .add(
///       @cli_source.CliSource::from_args(["-vq", "--no-verbose"])
///       .with_short_flag("v", "verbose")
///       .with_short_flag("q", "quiet"),
///     )
///     .build()
///   assert_false(cfg.get_bool("verbose"))
///   assert_true(cfg.get_bool("quiet"))
/// }
/// ```
pub fn CliSource::with_short_flag(
  self : CliSource,
  short : String,
  key : String,
) -> CliSource {
  self.shorts[short_name(short)] = { key, takes_value: false, }
  self
}

///|
/// 把一个路径声明成数组：同一个参数写几次就按顺序收进数组
///
/// 只写一次也得到单元素数组，不会一会儿是标量、一会儿是数组。
/// `-` 和 `.` 都按层级分隔符处理，和参数名的规则一致。
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = @config.Config::new()
///     .add(
///       @cli_source.CliSource::from_args(["--tag=a", "--tag=b", "--tag=c"]).with_array(
///         "tag",
///       ),
///     )
///     .build()
///   assert_true(
///     cfg.get_value("tag").kind is @config.ValueKind::Array(items) &&
///     items.length() == 3,
///   )
/// }
/// ```
pub fn CliSource::with_array(self : CliSource, key : String) -> CliSource {
  self.arrays[normalize_key(key)] = ()
  self
}

///|
/// 把第 `index` 个位置参数映射到配置路径 `key`
///
/// 位置只数非选项参数：选项本身和它吃掉的值跳过，`--` 之后全部算位置参数。
/// 从 0 开始；`new()` 不数可执行文件名，`from_args` 默认把整张表都当参数。
/// 同一个位置没声明就不进配置；同一个 key 被多个位置映射时后写的赢，
/// 声明成数组则按顺序累加。
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = @config.Config::new()
///     .add(
///       @cli_source.CliSource::from_args(
///         ["moonfmi", "simulate", "model.fmu", "--start", "0"],
///         program_name=true,
///       )
///       .with_value_style(@cli_source.CliValueStyle::Separate)
///       .with_positional(0, "command")
///       .with_positional(1, "model"),
///     )
///     .build()
///   assert_eq(cfg.get_string("command"), "simulate")
///   assert_eq(cfg.get_string("model"), "model.fmu")
///   assert_eq(cfg.get_int("start"), 0L)
/// }
/// ```
pub fn CliSource::with_positional(
  self : CliSource,
  index : Int32,
  key : String,
) -> CliSource {
  self.positionals[index] = key
  self
}

///|
pub impl @config.Source for CliSource with fn collect(self : CliSource) -> @config.Layer raise @config.ConfigError {
  let root : Map[String, @config.Value] = Map([])
  let seen : Map[String, String] = Map([])
  let mut index = 0
  let mut position = 0
  let mut after_terminator = false
  while index < self.args.length() {
    let arg = self.args[index]
    let raw = index
    index = index + 1
    if self.program_name && raw == 0 {
      continue
    }
    if !after_terminator {
      if arg == "--" {
        after_terminator = true
        continue
      }
      if arg.has_prefix("--") {
        index = parse_long(
          self,
          root,
          seen,
          arg.strip_prefix("--").unwrap(),
          index,
        )
        continue
      }
      if arg.has_prefix("-") && arg.length() > 1 {
        index = parse_short(
          self,
          root,
          seen,
          arg.strip_prefix("-").unwrap(),
          index,
        )
        continue
      }
    }
    assign_positional(self, root, seen, position, raw, arg)
    position = position + 1
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
/// 拆一条长选项，返回下一个还没读的参数下标
fn parse_long(
  source : CliSource,
  root : Map[String, @config.Value],
  seen : Map[String, String],
  rest : StringView,
  index : Int32,
) -> Int32 raise @config.ConfigError {
  if rest.length() == 0 {
    return index
  }
  match rest.split_once("=") {
    Some(pair) => {
      let key = pair.0
      let name = "--\{key}"
      if source.value_style == CliValueStyle::Separate {
        raise @config.ConfigError::ParseError(
          "argument cli:\{name}: style Separate expects cli:\{name} value, not cli:\{name}=value",
        )
      }
      assign(source, root, seen, key_path(key), name, literal_arg(pair.1, name))
      index
    }
    None => {
      let key = rest
      let name = "--\{key}"
      match key.strip_prefix("no-") {
        Some(inner) => {
          assign(
            source,
            root,
            seen,
            key_path(inner),
            name,
            @config.Value::bool(false),
          )
          index
        }
        None =>
          if source.value_style == CliValueStyle::Separate &&
            next_is_value(source, index) {
            assign(
              source,
              root,
              seen,
              key_path(key),
              name,
              literal_arg(source.args[index], name),
            )
            index + 1
          } else {
            assign(
              source,
              root,
              seen,
              key_path(key),
              name,
              @config.Value::bool(true),
            )
            index
          }
      }
    }
  }
}

///|
/// 拆一条短选项（可以是一串布尔短选项），返回下一个还没读的参数下标
fn parse_short(
  source : CliSource,
  root : Map[String, @config.Value],
  seen : Map[String, String],
  rest : StringView,
  index : Int32,
) -> Int32 raise @config.ConfigError {
  let mut cursor = index
  let mut pos = 0
  while pos < rest.length() {
    let name = rest.view(start_offset=pos, end_offset=pos + 1).to_owned()
    pos = pos + 1
    let short = match source.shorts.get(name) {
      Some(short) => short
      None => continue
    }
    let label = "-\{name}"
    let remainder = rest.view(start_offset=pos)
    if !short.takes_value {
      if remainder.strip_prefix("=") is Some(_) {
        raise @config.ConfigError::ParseError(
          "option cli:\{label}: a flag takes no value; write cli:\{short.key} or cli:--no-\{short.key}",
        )
      }
      assign(
        source,
        root,
        seen,
        key_path(short.key),
        label,
        @config.Value::bool(true),
      )
      continue
    }
    match source.value_style {
      CliValueStyle::Equals =>
        match remainder.strip_prefix("=") {
          Some(value) => {
            assign(
              source,
              root,
              seen,
              key_path(short.key),
              label,
              literal_arg(value, label),
            )
            return cursor
          }
          None =>
            raise @config.ConfigError::ParseError(
              "option cli:\{label}: style Equals expects cli:\{label}=value",
            )
        }
      CliValueStyle::Separate =>
        if remainder.length() > 0 {
          raise @config.ConfigError::ParseError(
            "option cli:\{label}: style Separate expects cli:\{label} value",
          )
        } else if next_is_value(source, cursor) {
          let value = source.args[cursor]
          cursor = cursor + 1
          assign(
            source,
            root,
            seen,
            key_path(short.key),
            label,
            literal_arg(value, label),
          )
          return cursor
        } else {
          raise @config.ConfigError::ParseError(
            "option cli:\{label}: requires a value",
          )
        }
    }
  }
  cursor
}

///|
/// 后面的参数能不能当上一项的值：有、且不以 `-` 开头（`-` 单独一个也算值）
fn next_is_value(source : CliSource, index : Int32) -> Bool {
  if index >= source.args.length() {
    return false
  }
  let next = source.args[index]
  next == "-" || !next.has_prefix("-")
}

///|
/// 短选项名归一化：去掉一个前导 `-`
fn short_name(short : String) -> String {
  match short.strip_prefix("-") {
    Some(rest) => rest.to_owned()
    None => short
  }
}

///|
/// 把参数名按和 `key_path` 一样的规则拼成路径串，供 `with_array` 比对
fn normalize_key(key : StringView) -> String {
  let text = StringBuilder()
  for c in key {
    if c == '-' || c == '.' {
      text.write_char('.')
    } else {
      text.write_char(c.to_ascii_lowercase())
    }
  }
  text.to_string()
}

///|
/// 字面值转 `Value`，报错时带上参数名
fn literal_arg(
  text : StringView,
  name : String,
) -> @config.Value raise @config.ConfigError {
  @config.Value::from_literal(text) catch {
    @config.ConfigError::ParseError(message) =>
      raise @config.ConfigError::ParseError("argument cli:\{name}: \{message}")
    error => raise error
  }
}

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
/// 位置参数按声明映射进树；没声明的位置直接忽略。
fn assign_positional(
  source : CliSource,
  root : Map[String, @config.Value],
  seen : Map[String, String],
  position : Int32,
  raw : Int32,
  value : String,
) -> Unit raise @config.ConfigError {
  match source.positionals.get(position) {
    Some(key) => {
      let name = "argv[\{raw}]"
      assign(source, root, seen, key_path(key), name, literal_arg(value, name))
    }
    None => ()
  }
}

///|
/// 顺着层级路径写入，中间缺的层顺手建出来。
fn assign(
  source : CliSource,
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
    if source.arrays.contains(joined) {
      raise @config.ConfigError::ParseError(
        "argument cli:\{name}: \{joined} is declared as an array and cannot be used as a path segment",
      )
    }
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
  let plural = source.arrays.contains(joined)
  match cur.get(leaf) {
    Some(existing) =>
      match existing.kind {
        @config.ValueKind::Table(_) =>
          raise @config.ConfigError::ParseError(
            "argument cli:\{name}: \{joined} already has configuration below it and cannot be replaced wholesale",
          )
        @config.ValueKind::Array(items) =>
          if plural {
            items.push(value)
          } else {
            raise @config.ConfigError::ParseError(
              "argument cli:\{name}: \{joined} is already an array and cannot be replaced by a single value",
            )
          }
        k =>
          if plural {
            raise @config.ConfigError::ParseError(
              "argument cli:\{name}: \{joined} is already \{k.name()} and cannot be turned into an array",
            )
          } else {
            cur[leaf] = value
          }
      }
    None =>
      if plural {
        cur[leaf] = @config.Value::array([value])
      } else {
        cur[leaf] = value
      }
  }
  seen[joined] = name
}
