///|
/// TOML 来源：文本 → `Value`，解析交给 `moonbit-community/toml`。
///
/// **支持 TOML 1.0 与 1.1。** 段落 `[section]`、段落的数组 `[[section]]`、
/// 点号键 `a.b = 1`、行内表 `{a = 1}`、数组、多行字符串、注释都能读。
/// 完整的语法边界以 `moonbit-community/toml` 为准。
///
/// **类型按 TOML 的类型走。** 字符串、整数（`Int64`）、浮点、布尔都是原样；
/// TOML 没有 null。日期时间（`1979-05-27T07:32:00Z` 这类）在 `Value` 里没有
/// 对应的形状，按原文当字符串存——需要别的处理就自己用 `get_string` 取出来再解析。
///
/// **数组要求同类型。** TOML 规定数组里的元素得是同一种类型，混着写的
/// 数组报错，不会悄悄读进来。
///
/// 根节点永远是一张表。段落名里的 `.` 直接变成层级，和 `Value::get_path` 对得上；
/// 键名里的 `.` 只有写成点号键（`a.b = 1`）时才是层级。
pub struct TomlSource {
  text : String
}

///|
/// 从 TOML 文本构造
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = @config.Config::new()
///     .add(
///       @toml_source.TomlSource::from_str(
///         "[db]\nhost = \"localhost\"\nport = 5432\n",
///       ),
///     )
///     .build()
///   assert_eq(cfg.get_string("db.host"), "localhost")
///   assert_eq(cfg.get_int("db.port"), 5432L)
/// }
/// ```
pub fn TomlSource::from_str(text : String) -> TomlSource {
  TomlSource::{ text, }
}

///|
pub impl @config.Source for TomlSource with fn collect(self : TomlSource) -> @config.Value raise @config.ConfigError {
  parse_toml(self.text)
}

///|
pub extend TomlSource with @config.Source::{collect}

///|
/// TOML 文本 → `Value`。
fn parse_toml(text : String) -> @config.Value raise @config.ConfigError {
  let parsed = @toml.parse(text) catch {
    e => raise @config.ConfigError::ParseError(e.to_string())
  }
  if !parsed.validate() {
    raise @config.ConfigError::ParseError(
      "数组里的元素必须是同一种类型",
    )
  }
  toml_root_to_value(parsed)
}

///|
/// 根节点 → `Value`。根节点必须是一张表。
fn toml_root_to_value(
  v : @toml.TomlValue,
) -> @config.Value raise @config.ConfigError {
  match v {
    @toml.TomlValue::TomlTable(table) => toml_table_to_value(table)
    v =>
      raise @config.ConfigError::ParseError(
        "TOML 的根节点必须是表，实际是 \{v.type_name()}",
      )
  }
}

///|
/// 表 → `Value`。
fn toml_table_to_value(
  table : Map[String, @toml.TomlValue],
) -> @config.Value raise @config.ConfigError {
  let out : Map[String, @config.Value] = Map([])
  for k, v in table {
    out[k] = toml_to_value(v)
  }
  @config.Value::table(out)
}

///|
/// `TomlValue` → `Value`。日期时间没有对应的形状，按原文当字符串。
fn toml_to_value(
  v : @toml.TomlValue,
) -> @config.Value raise @config.ConfigError {
  match v {
    @toml.TomlValue::TomlString(s) => @config.Value::str(s)
    @toml.TomlValue::TomlInteger(i) => @config.Value::int(i)
    @toml.TomlValue::TomlFloat(f) => @config.Value::float(f)
    @toml.TomlValue::TomlBoolean(b) => @config.Value::bool(b)
    @toml.TomlValue::TomlArray(arr) =>
      @config.Value::array(arr.map(toml_to_value))
    @toml.TomlValue::TomlTable(t) => toml_table_to_value(t)
    @toml.TomlValue::TomlDateTime(dt) => @config.Value::str(datetime_text(dt))
  }
}

///|
/// 日期时间的原文。四种写法（带时区、不带时区、只有日期、只有时间）都取
/// 括号里那段，丢掉类型名。
fn datetime_text(dt : @toml.TomlDateTime) -> String {
  match dt {
    @toml.TomlDateTime::OffsetDateTime(s)
    | @toml.TomlDateTime::LocalDateTime(s)
    | @toml.TomlDateTime::LocalDate(s)
    | @toml.TomlDateTime::LocalTime(s) => s
  }
}
