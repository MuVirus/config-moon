///|
/// YAML 来源：文本 → `Value`，解析交给 `moonbit-community/yaml`。
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
pub struct YamlSource {
  text : String
}

///|
/// 从 YAML 文本构造
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = @config.Config::new()
///     .add(
///       @yaml_source.YamlSource::from_str(
///         "db:\n  host: localhost\n  port: 5432\ndebug: false\n",
///       ),
///     )
///     .build()
///   assert_eq(cfg.get_string("db.host"), "localhost")
///   assert_eq(cfg.get_int("db.port"), 5432L)
///   assert_false(cfg.get_bool("debug"))
/// }
/// ```
pub fn YamlSource::from_str(text : String) -> YamlSource {
  YamlSource::{ text, }
}

///|
pub impl @config.Source for YamlSource with fn collect(self : YamlSource) -> @config.Value raise @config.ConfigError {
  parse_yaml(self.text)
}

///|
pub extend YamlSource with @config.Source::{collect}

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
/// 浮点值里混着「整数溢出 Int64，被库降级成 Double」的情况。
/// 原文还是整数形状就按 `Int64` 解析，塞不下就报错，不静默丢精度。
fn real_to_value(
  d : Double,
  repr : String,
) -> @config.Value raise @config.ConfigError {
  if is_int_literal(repr) {
    let i = @string.parse_int64(repr) catch {
      _ =>
        raise @config.ConfigError::ParseError(
          "整数 \{repr} 超出 Int64 范围",
        )
    }
    @config.Value::int(i)
  } else {
    @config.Value::float(d)
  }
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
