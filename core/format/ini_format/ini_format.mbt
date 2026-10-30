///|
/// INI 格式：文本 → `Value`，只用标准库的包，没有第三方依赖。
///
/// **段落决定层级。** `[db]` 段里的 `port = 5432` 落在 `db.port`；段落名里的
/// `.` 也算层级（`[db.pool]` → `db.pool`），和 `Value::get_path` 对得上。
/// 没有段落头的键落在根上，空段落不产生任何键。
///
/// **值按字面猜类型。** `true` / `false` 是布尔，整数按 `Int64` 解析（带小数点
/// 或指数的是浮点），其余都是字符串。引号包住的（`"…"` / `'…'`）不猜类型，
/// 原样当字符串——`color = "#ff0000"` 正是要这个。
///
/// **不剥行内注释。** `;` 和 `#` 只有在整行开头才算注释，否则 `color = #ff0000`
/// 会被截断。键值用 `=` 或 `:` 分开，两边都去空白。同名键、重复段落都是
/// 后写的赢，和合并规则一致。
pub struct IniFormat {}

///|
/// 构造 INI 格式
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = @config.Config::new()
///     .add(
///       @config.StringSource::new(
///         "[db]\nhost = localhost\nport = 5432\n",
///         @ini_format.IniFormat::new(),
///       ),
///     )
///     .build()
///   assert_eq(cfg.get_string("db.host"), "localhost")
///   assert_eq(cfg.get_int("db.port"), 5432L)
/// }
/// ```
pub fn IniFormat::new() -> IniFormat {
  IniFormat::{ }
}

///|
pub impl @config.Format for IniFormat with fn decode(
  _ : IniFormat,
  bytes : Bytes,
) -> @config.Value raise @config.ConfigError {
  let text = @utf8.decode(bytes) catch {
    _ => raise @config.ConfigError::ParseError("INI content is not valid UTF-8")
  }
  parse_ini(text)
}

///|
pub extend IniFormat with @config.Format::{decode}

///|
/// 单看内容和 `.env` 分不开，所以只认后缀，不参与内容判断。
pub impl @config.Format for IniFormat with fn suffixes(_ : IniFormat) -> Array[
  String,
] {
  ["ini"]
}

///|
pub extend IniFormat with @config.Format::{decode_path, suffixes, sniff}

///|
/// INI 文本 → `Value`。
fn parse_ini(text : String) -> @config.Value raise @config.ConfigError {
  let root : Map[String, @config.Value] = Map([])
  let mut section : Array[String] = []
  let mut section_line = 0
  let mut lineno = 0
  for raw in text.split("\n") {
    lineno += 1
    let line = raw.trim()
    if line.length() == 0 || line[0] == ';' || line[0] == '#' {
      continue
    }
    if line[0] == '[' {
      section = parse_section(line, lineno)
      section_line = lineno
      continue
    }
    let (key, rest) = split_pair(line, lineno)
    section_table(root, section, section_line)[key] = parse_scalar(rest, lineno)
  }
  @config.Value::table(root)
}

///|
/// `[name]` → 层级路径。段落名里的 `.` 拆成多层。
fn parse_section(
  line : StringView,
  lineno : Int32,
) -> Array[String] raise @config.ConfigError {
  if !line.has_suffix("]") {
    raise @config.ConfigError::ParseError(
      "line \{lineno}: section header \{line} is missing the closing ']'",
    )
  }
  let name = slice(line, 1, line.length() - 1).trim()
  let path = []
  for part in name.split(".") {
    let seg = part.trim()
    if seg.length() == 0 {
      raise @config.ConfigError::ParseError(
        "line \{lineno}: section name \{name} has an empty segment",
      )
    }
    path.push(seg.to_owned())
  }
  if path.length() == 0 {
    raise @config.ConfigError::ParseError(
      "line \{lineno}: section name is empty",
    )
  }
  path
}

///|
/// 一行拆成键和值，值交给调用方去猜类型。
fn split_pair(
  line : StringView,
  lineno : Int32,
) -> (String, StringView) raise @config.ConfigError {
  let key = StringBuilder()
  let val = StringBuilder()
  let mut found = false
  for c in line {
    if !found && (c == '=' || c == ':') {
      found = true
    } else if found {
      val.write_char(c)
    } else {
      key.write_char(c)
    }
  }
  if !found {
    raise @config.ConfigError::ParseError(
      "line \{lineno}: \{line} is missing '=' or ':'",
    )
  }
  let name = key.to_string().trim()
  if name.length() == 0 {
    raise @config.ConfigError::ParseError("line \{lineno}: key name is empty")
  }
  (name.to_owned(), val.to_string().trim())
}

///|
/// 顺着段落路径找到该写进去的那张表，中间缺的层顺手建出来。
/// 报错指向段落头那一行，不是撞上它的键那一行。
fn section_table(
  root : Map[String, @config.Value],
  path : Array[String],
  section_line : Int32,
) -> Map[String, @config.Value] raise @config.ConfigError {
  let mut cur = root
  for seg in path {
    let next = match cur.get(seg) {
      Some(v) =>
        match v.kind {
          @config.ValueKind::Table(t) => t
          k =>
            raise @config.ConfigError::ParseError(
              "line \{section_line}: \{seg} is already \{k.name()} and cannot be used as a section name",
            )
        }
      None => {
        let t : Map[String, @config.Value] = Map([])
        cur[seg] = @config.Value::table(t)
        t
      }
    }
    cur = next
  }
  cur
}

///|
/// 值 → `Value`。引号包住的原样当字符串，其余按字面猜类型。
fn parse_scalar(
  s : StringView,
  lineno : Int32,
) -> @config.Value raise @config.ConfigError {
  if is_quoted(s) {
    return @config.Value::str(slice(s, 1, s.length() - 1).to_owned())
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
            "line \{lineno}: \{s} is not a valid float",
          )
      },
    )
  }
  @config.Value::str(s.to_owned())
}

///|
fn is_quoted(s : StringView) -> Bool {
  if s.length() < 2 {
    return false
  }
  let first = s[0]
  (first == '"' || first == '\'') && s[s.length() - 1] == first
}

///|
/// 整数按 `Int64` 解析，大整数不丢；超出范围报错，不静默截断。
fn int_of(s : StringView, lineno : Int32) -> Int64 raise @config.ConfigError {
  @string.parse_int64(s) catch {
    _ =>
      raise @config.ConfigError::ParseError(
        "line \{lineno}: integer \{s} exceeds Int64 range",
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
