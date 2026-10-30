///|
/// XML 格式：文本 → `Value`，解析交给 `Milky2018/xml`。
///
/// **元素名就是键名。** 元素的子元素变成一张表，键是子元素的名字。同名兄弟
/// 元素出现多次时，那个键的值是数组，只有一个时是那个值本身。
///
/// **根元素只是个壳。** 根元素的名字不参与取值，它的子元素直接落在顶层，
/// 所以 `<config><db><host>x</host></db></config>` 里 `host` 在 `db` 下面。
/// 根元素自己的属性落在 `@` 开头的键上。
///
/// **文字按字面猜类型。** 和 INI、`.env` 一样：没加引号（XML 也没有引号这回事）
/// 的 `true` / `false` 是布尔，整数按 `Int64` 解析，带小数点或指数的是浮点，
/// 其余都是字符串。文字里的首尾空白不算数，空元素是空字符串。
///
/// **CDATA 一定是字符串。** CDATA 的意思就是「这段是字面文字，不要解释」，
/// 所以 `<version><![CDATA[1.0]]></version>` 是字符串 `"1.0"`，不是浮点。
/// 想要字符串就用 CDATA，这是 XML 本身给的办法。属性值没有这个办法，
/// 属性值一律按字面猜类型。
///
/// **属性放在 `@` 前缀的键上。** 属性和子元素的名字可能撞车，所以属性写成
/// `@name`，和子元素的 `name` 分开。`<db host="localhost"/>` 落在 `@host` 上。
/// 命名空间声明（`xmlns` / `xmlns:foo`）不算属性，不进表里。
///
/// **混合内容放在 `#text` 上。** 元素既有子元素（或属性）又有文字时，文字落在
/// `#text` 键上；只有空白就当没有。
///
/// 命名空间前缀保留在名字里（`ns:tag` 就是 `ns:tag`），不同命名空间的同名
/// 元素不会撞车。注释、处理指令、DOCTYPE 和 XML 声明都被跳过，实体引用
/// （`&amp;` 这些）由解析器解好。
pub struct XmlFormat {}

///|
/// 构造 XML 格式
///
/// Example:
///
/// ```mbt check
/// test {
///   let cfg = @config.Config::new()
///     .add(
///       @config.StringSource::new(
///         "<config><db><host>localhost</host><port>5432</port></db></config>",
///         @xml_format.XmlFormat::new(),
///       ),
///     )
///     .build()
///   assert_eq(cfg.get_string("db.host"), "localhost")
///   assert_eq(cfg.get_int("db.port"), 5432L)
/// }
/// ```
pub fn XmlFormat::new() -> XmlFormat {
  XmlFormat::{ }
}

///|
pub impl @config.Format for XmlFormat with fn decode(
  _ : XmlFormat,
  bytes : Bytes,
) -> @config.Value raise @config.ConfigError {
  let text = @utf8.decode(bytes) catch {
    _ => raise @config.ConfigError::ParseError("XML content is not valid UTF-8")
  }
  parse_xml(text)
}

///|
pub extend XmlFormat with @config.Format::{decode}

///|
pub impl @config.Format for XmlFormat with fn suffixes(_ : XmlFormat) -> Array[
  String,
] {
  ["xml"]
}

///|
/// 第一个非空白字符是 `<` 就像 XML。
pub impl @config.Format for XmlFormat with fn sniff(
  _ : XmlFormat,
  bytes : Bytes,
) -> Bool {
  for byte in bytes {
    let code = byte.to_int()
    if code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D {
      continue
    }
    return code == 0x3C
  }
  false
}

///|
pub extend XmlFormat with @config.Format::{decode_path, suffixes, sniff}

///|
/// XML 文本 → `Value`。
fn parse_xml(text : String) -> @config.Value raise @config.ConfigError {
  match read_events(text) {
    Some(events) => parse_root(events)
    None => @config.Value::table(Map([]))
  }
}

///|
/// 读事件流。没有根元素的文档（空文件、只有注释）当配置读就是一张空表，
/// 返回 `None`。
fn read_events(text : String) -> Array[@xml.Event]? raise @config.ConfigError {
  let reader = @xml.Reader::from_string(text)
  let mut no_root = false
  let events = reader.read_events_until_eof() catch {
    e =>
      if is_no_root_element(e) {
        no_root = true
        []
      } else {
        raise @config.ConfigError::ParseError(xml_error_text(e))
      }
  }
  if no_root {
    None
  } else {
    Some(events)
  }
}

///|
/// 报错是不是「文档里没有根元素」。空文件和只有注释的文件都算。
fn is_no_root_element(e : @xml.XmlError) -> Bool {
  match e {
    @xml.XmlError::At(error~, ..) =>
      match error {
        @xml.XmlErrorKind::InvalidSyntax(m) =>
          m.contains("no root element") || m.contains("empty document")
        _ => false
      }
  }
}

///|
/// 从事件流里找出根元素。根元素是壳，它的内容就是整棵配置。
fn parse_root(
  events : Array[@xml.Event],
) -> @config.Value raise @config.ConfigError {
  let mut i = 0
  while i < events.length() {
    match events[i].kind {
      @xml.EventKind::Start(elem) => {
        let (children, text, is_literal, _) = parse_children(events, i + 1)
        return root_to_value(elem, children, text, is_literal)
      }
      @xml.EventKind::Empty(elem) => return root_to_value(elem, [], "", false)
      _ => i += 1
    }
  }
  @config.Value::table(Map([]))
}

///|
/// 解析一个元素的内容：返回子元素、直接文字、文字是不是字面量、下一个下标。
fn parse_children(
  events : Array[@xml.Event],
  start : Int32,
) -> (Array[XmlNode], String, Bool, Int32) {
  let children : Array[XmlNode] = []
  let text = StringBuilder()
  let mut has_cdata = false
  let mut has_plain = false
  let mut i = start
  while i < events.length() {
    match events[i].kind {
      @xml.EventKind::End(_) => {
        i += 1
        break
      }
      @xml.EventKind::Start(elem) => {
        let (kids, inner, is_literal, next) = parse_children(events, i + 1)
        children.push(XmlNode::Element(elem, kids, inner, is_literal))
        i = next
      }
      @xml.EventKind::Empty(elem) => {
        children.push(XmlNode::Element(elem, [], "", false))
        i += 1
      }
      @xml.EventKind::Text(s) => {
        text.write_string(s)
        if s.trim().length() > 0 {
          has_plain = true
        }
        i += 1
      }
      @xml.EventKind::CData(s) => {
        text.write_string(s)
        has_cdata = true
        i += 1
      }
      _ => i += 1
    }
  }
  let is_literal = has_cdata && !has_plain
  (children, text.to_string(), is_literal, i)
}

///|
/// 一个元素节点：标签本身、子元素、直接文字、文字是不是字面量。
priv enum XmlNode {
  Element(@xml.XmlElement, Array[XmlNode], String, Bool)
}

///|
/// 根元素 → `Value`。根是壳，属性、子元素、文字都摊到顶层。
fn root_to_value(
  elem : @xml.XmlElement,
  children : Array[XmlNode],
  text : String,
  is_literal : Bool,
) -> @config.Value raise @config.ConfigError {
  let table : Map[String, @config.Value] = Map([])
  put_attributes(table, elem)
  put_children(table, children)
  put_text(table, text, is_literal)
  @config.Value::table(table)
}

///|
/// 元素 → `Value`。没有子元素也没有属性时是文字本身，其余是一张表。
fn element_to_value(
  elem : @xml.XmlElement,
  children : Array[XmlNode],
  text : String,
  is_literal : Bool,
) -> @config.Value raise @config.ConfigError {
  if children.is_empty() && elem.attributes.is_empty() {
    return text_to_value(text, is_literal)
  }
  let table : Map[String, @config.Value] = Map([])
  put_attributes(table, elem)
  put_children(table, children)
  put_text(table, text, is_literal)
  @config.Value::table(table)
}

///|
/// 属性 → `@name` 键。命名空间声明不算属性。
fn put_attributes(
  table : Map[String, @config.Value],
  elem : @xml.XmlElement,
) -> Unit raise @config.ConfigError {
  for attr in elem.attributes {
    if is_namespace_decl(attr.name) {
      continue
    }
    table["@" + attr.name] = text_to_value(attr.value, false)
  }
}

///|
/// `xmlns` 或者 `xmlns:foo` 是命名空间声明，不是配置项。
fn is_namespace_decl(name : String) -> Bool {
  name == "xmlns" || name.has_prefix("xmlns:")
}

///|
/// 子元素 → 键。同名的兄弟元素收成数组，只有一个时是那个值本身。
fn put_children(
  table : Map[String, @config.Value],
  children : Array[XmlNode],
) -> Unit raise @config.ConfigError {
  let groups : Map[String, Array[@config.Value]] = Map([])
  for child in children {
    match child {
      XmlNode::Element(elem, kids, text, is_literal) => {
        let value = element_to_value(elem, kids, text, is_literal)
        match groups.get(elem.name) {
          Some(list) => list.push(value)
          None => groups[elem.name] = [value]
        }
      }
    }
  }
  for name, list in groups {
    table[name] = if list.length() == 1 {
      list[0]
    } else {
      @config.Value::array(list)
    }
  }
}

///|
/// 混合内容里的文字 → `#text` 键。只有空白就当没有。
fn put_text(
  table : Map[String, @config.Value],
  text : String,
  is_literal : Bool,
) -> Unit raise @config.ConfigError {
  let trimmed = text.trim().to_owned()
  if trimmed.length() > 0 {
    table["#text"] = text_to_value(trimmed, is_literal)
  }
}

///|
/// 文字 → `Value`。字面量（CDATA）一定是字符串，其余按字面猜类型。
fn text_to_value(
  text : String,
  is_literal : Bool,
) -> @config.Value raise @config.ConfigError {
  let trimmed = text.trim().to_owned()
  if is_literal {
    return @config.Value::str(trimmed)
  }
  if trimmed == "true" {
    return @config.Value::bool(true)
  }
  if trimmed == "false" {
    return @config.Value::bool(false)
  }
  if is_int_literal(trimmed) {
    return @config.Value::int(
      @string.parse_int64(trimmed) catch {
        _ =>
          raise @config.ConfigError::ParseError(
            "integer \{trimmed} exceeds Int64 range",
          )
      },
    )
  }
  if is_float_literal(trimmed) {
    return @config.Value::float(
      @string.parse_double(trimmed) catch {
        _ =>
          raise @config.ConfigError::ParseError(
            "\{trimmed} is not a valid float",
          )
      },
    )
  }
  @config.Value::str(trimmed)
}

///|
/// 整数形状：可选负号加一串数字。
fn is_int_literal(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let mut i = if s[0] == '-' { 1 } else { 0 }
  if i >= s.length() {
    return false
  }
  while i < s.length() {
    if !(s[i] >= '0' && s[i] <= '9') {
      return false
    }
    i += 1
  }
  true
}

///|
/// 浮点形状：小数或指数，两边都得有数字。
fn is_float_literal(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let mut i = if s[0] == '-' { 1 } else { 0 }
  let mut digits = 0
  while i < s.length() && s[i] >= '0' && s[i] <= '9' {
    digits += 1
    i += 1
  }
  if digits == 0 {
    return false
  }
  if i < s.length() && s[i] == '.' {
    i += 1
    let mut frac = 0
    while i < s.length() && s[i] >= '0' && s[i] <= '9' {
      frac += 1
      i += 1
    }
    if frac == 0 {
      return false
    }
  }
  if i < s.length() && (s[i] == 'e' || s[i] == 'E') {
    i += 1
    if i < s.length() && (s[i] == '-' || s[i] == '+') {
      i += 1
    }
    let mut exp = 0
    while i < s.length() && s[i] >= '0' && s[i] <= '9' {
      exp += 1
      i += 1
    }
    if exp == 0 {
      return false
    }
  }
  i == s.length()
}

///|
/// 解析错误的消息，带上行号列号。
fn xml_error_text(e : @xml.XmlError) -> String {
  match e {
    @xml.XmlError::At(error~, span~) => {
      let detail = match error {
        @xml.XmlErrorKind::UnexpectedEof => "unexpected end of document"
        @xml.XmlErrorKind::InvalidSyntax(m) => "syntax error: \{m}"
        @xml.XmlErrorKind::UnmatchedTag(expected~, found~) =>
          "mismatched tag: expected \{expected}, got \{found}"
        @xml.XmlErrorKind::InvalidAttribute(m) => "invalid attribute: \{m}"
        @xml.XmlErrorKind::InvalidEntity(m) => "invalid entity: \{m}"
      }
      "line \{span.start.line}, column \{span.start.column}: \{detail}"
    }
  }
}
