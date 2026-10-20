///|
/// `.env` 来源：文本 → `Value`，解析器自己写，没有第三方依赖。
///
/// **一行一个键值对。** `KEY=VALUE`，允许缩进，也允许 `export KEY=VALUE`
/// 这种前缀。没有 `=` 的行报错，不会默默忽略。
///
/// **键名里的 `.` 表示层级。** `db.host=localhost` 落在 `db.host`，和
/// `Value::get_path` 对得上；`DB_HOST` 是平铺的一个键，下划线不会自动变成点。
/// 键名区分大小写，原样保留。
///
/// **值按字面猜类型。** 没加引号时，`true` / `false` 是布尔，整数按 `Int64`
/// 解析（带小数点或指数的是浮点），其余都是字符串。引号包住的（`"…"` /
/// `'…'`）不猜类型，原样当字符串。空值是空字符串，不是 `Null`。
///
/// **引号。** 单引号里的内容一个字都不改；双引号认 `\n`、`\r`、`\t`、`\\`、
/// `\"`、`\'`、`\$` 这几个转义，其它反斜杠原样保留（`"C:\path"` 不会坏）。
/// 不支持跨行的引号值，也不做 `${VAR}` 变量展开——`$` 后面是什么就留什么。
///
/// **注释。** 整行开头的 `#` 是注释。行尾的 `#` 只有前面是空白时才算注释，
/// 所以 `KEY=#ff0000` 和 `KEY=abc#123` 里的 `#` 都属于值。
///
/// 同名键后写的赢；先写标量、后来又拿同一个名字当层级（`a=1` 后接
/// `a.b=2`）会报错，反过来则是后者整体覆盖前者。
pub struct DotenvSource {
  text : String
}

///|
/// 从 `.env` 文本构造
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = @config.Config::new()
///     .add(
///       @dotenv_source.DotenvSource::from_str(
///         "# 服务配置\nexport DB_HOST=localhost\nDB_PORT=5432\nDEBUG=false\n",
///       ),
///     )
///     .build()
///   assert_eq(cfg.get_string("DB_HOST"), "localhost")
///   assert_eq(cfg.get_int("DB_PORT"), 5432L)
///   assert_false(cfg.get_bool("DEBUG"))
/// }
/// ```
pub fn DotenvSource::from_str(text : String) -> DotenvSource {
  DotenvSource::{ text, }
}

///|
pub impl @config.Source for DotenvSource with fn collect(self : DotenvSource) -> @config.Value raise @config.ConfigError {
  parse_dotenv(self.text)
}

///|
pub extend DotenvSource with @config.Source::{collect}

///|
/// `.env` 文本 → `Value`。
fn parse_dotenv(text : String) -> @config.Value raise @config.ConfigError {
  let root : Map[String, @config.Value] = Map([])
  let mut lineno = 0
  for raw in text.split("\n") {
    lineno += 1
    let mut line = raw.trim()
    if lineno == 1 && line.has_prefix("\u{FEFF}") {
      line = slice(line, 1, line.length()).trim()
    }
    if line.has_prefix("export ") || line.has_prefix("export\t") {
      line = slice(line, 7, line.length()).trim()
    } else if line == "export" {
      raise @config.ConfigError::ParseError(
        "第 \{lineno} 行：export 后面缺少键值对",
      )
    }
    if line.length() == 0 || line.has_prefix("#") {
      continue
    }
    let (key, rest) = split_pair(line, lineno)
    let path = key_path(key, lineno)
    assign(root, path, parse_value(rest, lineno), lineno)
  }
  @config.Value::table(root)
}

///|
/// 一行拆成键和值。值保持原样，注释和引号交给 `parse_value`。
fn split_pair(
  line : StringView,
  lineno : Int32,
) -> (StringView, StringView) raise @config.ConfigError {
  let (key, rest) = match line.split_once("=") {
    Some(pair) => pair
    None =>
      raise @config.ConfigError::ParseError(
        "第 \{lineno} 行：\{line} 缺 `=`",
      )
  }
  let name = key.trim()
  if name.length() == 0 {
    raise @config.ConfigError::ParseError("第 \{lineno} 行：键名为空")
  }
  (name, rest)
}

///|
/// 键名 → 层级路径。键名里的 `.` 拆成多层，下划线不动。
fn key_path(
  key : StringView,
  lineno : Int32,
) -> Array[String] raise @config.ConfigError {
  let path : Array[String] = []
  for part in key.split(".") {
    let seg = part.trim()
    if seg.length() == 0 {
      raise @config.ConfigError::ParseError(
        "第 \{lineno} 行：键名 \{key} 有空的一层",
      )
    }
    for c in seg {
      if c == ' ' || c == '\t' {
        raise @config.ConfigError::ParseError(
          "第 \{lineno} 行：键名 \{key} 含空白",
        )
      }
    }
    path.push(seg.to_owned())
  }
  path
}

///|
/// 顺着层级路径找到该写进去的那张表，中间缺的层顺手建出来。
/// 名字已经被标量占了就报错，指向写出这个键的那一行。
fn assign(
  root : Map[String, @config.Value],
  path : Array[String],
  value : @config.Value,
  lineno : Int32,
) -> Unit raise @config.ConfigError {
  let mut cur = root
  let mut i = 0
  while i < path.length() - 1 {
    let seg = path[i]
    let next = match cur.get(seg) {
      Some(v) =>
        match v.kind {
          @config.ValueKind::Table(t) => t
          k =>
            raise @config.ConfigError::ParseError(
              "第 \{lineno} 行：\{seg} 已经是 \{k.name()}，不能当层级名",
            )
        }
      None => {
        let t : Map[String, @config.Value] = Map([])
        cur[seg] = @config.Value::table(t)
        t
      }
    }
    cur = next
    i += 1
  }
  cur[path[path.length() - 1]] = value
}

///|
/// 值 → `Value`。引号包住的原样当字符串，其余先去掉行尾注释再猜类型。
fn parse_value(
  raw : StringView,
  lineno : Int32,
) -> @config.Value raise @config.ConfigError {
  let trimmed = raw.trim()
  if trimmed.length() == 0 {
    return @config.Value::str("")
  }
  if trimmed.has_prefix("\"") {
    return parse_quoted(trimmed, true, lineno)
  }
  if trimmed.has_prefix("'") {
    return parse_quoted(trimmed, false, lineno)
  }
  infer_scalar(strip_comment(raw).trim(), lineno)
}

///|
/// 解析带引号的值。引号结束后只允许空白或注释，别的内容报错。
fn parse_quoted(
  text : StringView,
  double : Bool,
  lineno : Int32,
) -> @config.Value raise @config.ConfigError {
  let mut end : Int32 = -1
  let mut i : Int32 = 0
  let mut escaped = false
  for c in text {
    if i > 0 {
      if double && escaped {
        escaped = false
      } else if double && c == '\\' {
        escaped = true
      } else if (double && c == '"') || (!double && c == '\'') {
        end = i
        break
      }
    }
    i += 1
  }
  if end < 0 {
    let quote = if double { "双" } else { "单" }
    raise @config.ConfigError::ParseError(
      "第 \{lineno} 行：\{quote}引号没有闭合",
    )
  }
  let content = slice(text, 1, end)
  let tail = slice(text, end + 1, text.length()).trim()
  if tail.length() > 0 && !tail.has_prefix("#") {
    raise @config.ConfigError::ParseError(
      "第 \{lineno} 行：引号结束后还有内容 \{tail}",
    )
  }
  if double {
    @config.Value::str(unescape_double(content))
  } else {
    @config.Value::str(content.to_owned())
  }
}

///|
/// 双引号里的转义。不认识的转义原样保留反斜杠，Windows 路径不会被吃掉。
fn unescape_double(s : StringView) -> String {
  let out = StringBuilder()
  let mut escaped = false
  for c in s {
    if escaped {
      match c {
        'n' => out.write_char('\n')
        'r' => out.write_char('\r')
        't' => out.write_char('\t')
        '\\' => out.write_char('\\')
        '"' => out.write_char('"')
        '\'' => out.write_char('\'')
        '$' => out.write_char('$')
        _ => {
          out.write_char('\\')
          out.write_char(c)
        }
      }
      escaped = false
    } else if c == '\\' {
      escaped = true
    } else {
      out.write_char(c)
    }
  }
  if escaped {
    out.write_char('\\')
  }
  out.to_string()
}

///|
/// 去掉行尾注释：`#` 只有在前面是空白时才开始注释。
fn strip_comment(s : StringView) -> StringView {
  let mut prev_space = false
  let mut i : Int32 = 0
  for c in s {
    if c == '#' && prev_space {
      return slice(s, 0, i)
    }
    prev_space = c == ' ' || c == '\t'
    i += 1
  }
  s
}

///|
/// 没加引号的值 → `Value`，按字面猜类型。
fn infer_scalar(
  s : StringView,
  lineno : Int32,
) -> @config.Value raise @config.ConfigError {
  if s.length() == 0 {
    return @config.Value::str("")
  }
  if s == "true" {
    return @config.Value::bool(true)
  }
  if s == "false" {
    return @config.Value::bool(false)
  }
  let cs = chars_of(s)
  if is_int_literal(cs) {
    return @config.Value::int(int_of(s, lineno))
  }
  if is_float_literal(cs) {
    return @config.Value::float(
      @string.parse_double(s) catch {
        _ =>
          raise @config.ConfigError::ParseError(
            "第 \{lineno} 行：\{s} 不是合法的浮点数",
          )
      },
    )
  }
  @config.Value::str(s.to_owned())
}

///|
/// 整数按 `Int64` 解析，大整数不丢；超出范围报错，不静默截断。
fn int_of(s : StringView, lineno : Int32) -> Int64 raise @config.ConfigError {
  @string.parse_int64(s) catch {
    _ =>
      raise @config.ConfigError::ParseError(
        "第 \{lineno} 行：整数 \{s} 超出 Int64 范围",
      )
  }
}

///|
/// 整数形状：可选负号加一串数字。
fn is_int_literal(cs : Array[Char]) -> Bool {
  if cs.length() == 0 {
    return false
  }
  let mut i = if cs[0] == '-' { 1 } else { 0 }
  if i >= cs.length() {
    return false
  }
  while i < cs.length() {
    if !is_digit(cs[i]) {
      return false
    }
    i += 1
  }
  true
}

///|
/// 浮点形状：小数或指数，两边都得有数字。
/// 形状卡死是为了让 `@string.parse_double` 不会真的抛错——它一抛就是配置坏了。
fn is_float_literal(cs : Array[Char]) -> Bool {
  if cs.length() == 0 {
    return false
  }
  let mut i = if cs[0] == '-' { 1 } else { 0 }
  let mut digits = 0
  while i < cs.length() && is_digit(cs[i]) {
    digits += 1
    i += 1
  }
  if digits == 0 {
    return false
  }
  if i < cs.length() && cs[i] == '.' {
    i += 1
    let mut frac = 0
    while i < cs.length() && is_digit(cs[i]) {
      frac += 1
      i += 1
    }
    if frac == 0 {
      return false
    }
  }
  if i < cs.length() && (cs[i] == 'e' || cs[i] == 'E') {
    i += 1
    if i < cs.length() && (cs[i] == '-' || cs[i] == '+') {
      i += 1
    }
    let mut exp = 0
    while i < cs.length() && is_digit(cs[i]) {
      exp += 1
      i += 1
    }
    if exp == 0 {
      return false
    }
  }
  i == cs.length()
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// `StringView` 按下标取出来的是 `UInt16`，猜类型这里要的是 `Char`，先摊成数组。
fn chars_of(s : StringView) -> Array[Char] {
  let out = []
  for c in s {
    out.push(c)
  }
  out
}

///|
/// 取 `[from, to)` 这一段。`StringView` 的切片在写循环时反而更省心。
fn slice(s : StringView, from : Int32, to : Int32) -> StringView {
  let b = StringBuilder()
  let mut i = 0
  for c in s {
    if i >= from && i < to {
      b.write_char(c)
    }
    i += 1
  }
  b.to_string()
}
