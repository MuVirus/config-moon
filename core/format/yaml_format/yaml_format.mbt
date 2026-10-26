///|
/// YAML 格式：文本 → `Value`，解析交给 `moonbit-community/yaml`。
///
/// **支持的是常用 YAML 子集。** 块映射、块序列、流式集合、引号标量、
/// 块标量、注释、锚点和别名都能读；映射的键必须是字符串，重复键由库报错。
/// 完整的语法边界以 `moonbit-community/yaml` 为准。
///
/// **只接受一个文档。** 一个文件里用 `---` 分成多段时报错，不会悄悄只取第一段。
/// 空文件、空文档、只有注释的文件，以及根节点为 `null` 的文件，得到一棵空表。
///
/// **类型按 YAML 标签走。** 未加引号的 `true` / `false`、整数、浮点是布尔、
/// `Int64`、浮点；`null` / `~` 是 `Null`；引号包住的一律是字符串。整数超出
/// `Int64` 时报错，不静默变成浮点。时间戳之类 YAML 里没有标签的写法保持字符串。
///
/// 配置的根节点通常应该是一张映射；根节点是标量或数组时也能读进来，只是
/// 路径取值没有意义。层级直接由 YAML 的嵌套结构决定，键名里的 `.` 不拆分。
pub struct YamlFormat {}

///|
/// 构造 YAML 格式
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = @config.Config::new()
///     .add(
///       @config.StringSource::new(
///         "db:\n  host: localhost\n  port: 5432\ndebug: false\n",
///         @yaml_format.YamlFormat::new(),
///       ),
///     )
///     .build()
///   assert_eq(cfg.get_string("db.host"), "localhost")
///   assert_eq(cfg.get_int("db.port"), 5432L)
///   assert_false(cfg.get_bool("debug"))
/// }
/// ```
pub fn YamlFormat::new() -> YamlFormat {
  YamlFormat::{ }
}

///|
pub impl @config.Format for YamlFormat with fn decode(
  _ : YamlFormat,
  bytes : Bytes,
) -> @config.Value raise @config.ConfigError {
  let text = @utf8.decode(bytes) catch {
    _ =>
      raise @config.ConfigError::ParseError("YAML 内容不是合法的 UTF-8")
  }
  parse_yaml(text)
}

///|
pub extend YamlFormat with @config.Format::{decode}

///|
pub impl @config.Format for YamlFormat with fn suffixes(_ : YamlFormat) -> Array[
  String,
] {
  ["yaml", "yml"]
}

///|
/// 顶层有 `key:` 或 `- ` 就像 YAML；缩进行不算顶层。
fn yaml_key_line(line : StringView) -> Bool {
  if line.has_prefix("{") || line.has_prefix("[") {
    return false
  }
  match line.split_once(":") {
    Some((key, value)) => {
      let key = key.trim_end()
      if key.is_empty() {
        false
      } else if value.is_empty() {
        true
      } else {
        // 块映射要求冒号后面是空白；`http://...` 这种不算
        value.has_prefix(" ")
      }
    }
    None => false
  }
}

///|
pub impl @config.Format for YamlFormat with fn sniff(
  _ : YamlFormat,
  bytes : Bytes,
) -> Bool {
  let text = @utf8.decode(bytes) catch { _ => return false }
  for raw in text.split("\n") {
    let line = raw.trim_end()
    if line.is_empty() {
      continue
    }
    let top = line.trim_start()
    if top.length() != line.length() {
      continue // 缩进行不是顶层
    }
    if top.has_prefix("#") ||
      top.has_prefix("%") ||
      top.equal_to_string("---") ||
      top.equal_to_string("...") {
      continue
    }
    if top.equal_to_string("-") || top.has_prefix("- ") {
      return true
    }
    if yaml_key_line(top) {
      return true
    }
  }
  false
}

///|
pub extend YamlFormat with @config.Format::{decode_path, suffixes, sniff}

///|
/// YAML 文本 → `Value`。
fn parse_yaml(text : String) -> @config.Value raise @config.ConfigError {
  let docs = @yaml.Yaml::load_from_string(text) catch {
    @yaml.YamlError(info~, ..) => raise @config.ConfigError::ParseError(info)
  }
  match docs {
    [] => @config.Value::table(Map([]))
    [doc] =>
      match doc {
        @yaml.Yaml::BadValue | @yaml.Yaml::Null => @config.Value::table(Map([]))
        _ => yaml_to_value(doc)
      }
    _ =>
      raise @config.ConfigError::ParseError(
        "YAML 文本包含多个文档，只支持一个",
      )
  }
}

///|
/// `Yaml` → `Value`。整数保持 `Int64`，数组和映射递归转换。
fn yaml_to_value(y : @yaml.Yaml) -> @config.Value raise @config.ConfigError {
  match y {
    @yaml.Yaml::Real(d, repr~) => real_to_value(d, repr)
    @yaml.Yaml::Integer(i) => @config.Value::int(i)
    @yaml.Yaml::String(s) => @config.Value::str(s)
    @yaml.Yaml::Boolean(b) => @config.Value::bool(b)
    @yaml.Yaml::Array(arr) => @config.Value::array(arr.map(yaml_to_value))
    @yaml.Yaml::Map(m) => {
      let table : Map[String, @config.Value] = Map([])
      for k, v in m {
        table[k] = yaml_to_value(v)
      }
      @config.Value::table(table)
    }
    @yaml.Yaml::Null => @config.Value::null()
    @yaml.Yaml::BadValue =>
      raise @config.ConfigError::ParseError("YAML 里有无法表示的值")
  }
}

///|
/// `Yaml::Real` 有两种来源：写了小数点／指数的浮点，以及「整数溢出 `Int64`，
/// 被库降级成 `Double`」。
///
/// 能塞进 `Int64` 的整数形状只可能来自显式的 `!!float 2`：普通整数在 YAML
/// 库里先走 `Integer` 分支，不会进到这里。所以这里一律保留 `Float`，不能拿
/// 原文的整数形状反推成 `Int`——那会让浮点来源混进整数字段。
///
/// 塞不下的整数形状仍然报错，不静默丢精度。
fn real_to_value(
  d : Double,
  repr : String,
) -> @config.Value raise @config.ConfigError {
  if is_int_literal(repr) {
    let _ = @string.parse_int64(repr) catch {
      _ =>
        raise @config.ConfigError::ParseError(
          "整数 \{repr} 超出 Int64 范围",
        )
    }
  }
  @config.Value::float(d)
}

///|
/// 整数形状：可选正负号加一串数字。
fn is_int_literal(s : String) -> Bool {
  let mut first = true
  let mut digits = 0
  for c in s {
    if first && (c == '-' || c == '+') {
      first = false
    } else if c >= '0' && c <= '9' {
      first = false
      digits += 1
    } else {
      return false
    }
  }
  digits > 0
}
