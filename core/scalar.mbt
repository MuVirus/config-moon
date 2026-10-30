///|
/// 把一段字面文本猜成配置值。
///
/// - `true` / `false` → `Bool`
/// - 整数写法 → `Int`（`Int64`），超出范围报错，不降级成浮点
/// - 带小数点或指数的写法 → `Float`
/// - 其余 → 字符串，空文本是空字符串
///
/// 环境变量和命令行参数全是字符串，类型推断必须在这一层做完：等到按结构体取值时，
/// 标准库的 `Bool::from_json` / `Double::from_json` 都拒收字符串。
pub fn Value::from_literal(text : StringView) -> Value raise ConfigError {
  if text == "true" {
    return Value::bool(true)
  }
  if text == "false" {
    return Value::bool(false)
  }
  let chars = chars_of(text)
  if is_int_literal(chars) {
    return Value::int(parse_int(text))
  }
  if is_float_literal(chars) {
    return Value::float(
      @string.parse_double(text) catch {
        _ => raise ConfigError::ParseError("\{text} is not a valid float")
      },
    )
  }
  Value::str(text.to_owned())
}

///|
/// 整数按 `Int64` 解析，大整数不丢；超出范围报错。
fn parse_int(text : StringView) -> Int64 raise ConfigError {
  @string.parse_int64(text) catch {
    _ => raise ConfigError::ParseError("integer \{text} exceeds Int64 range")
  }
}

///|
/// 整数形状：可选负号加一串数字。
fn is_int_literal(chars : Array[Char]) -> Bool {
  if chars.length() == 0 {
    return false
  }
  let mut i = if chars[0] == '-' { 1 } else { 0 }
  if i >= chars.length() {
    return false
  }
  while i < chars.length() {
    if !is_digit(chars[i]) {
      return false
    }
    i += 1
  }
  true
}

///|
/// 浮点形状：小数或指数，两边都得有数字。
/// 形状卡死是为了让 `@string.parse_double` 不会真的抛错——它一抛就是配置坏了。
fn is_float_literal(chars : Array[Char]) -> Bool {
  if chars.length() == 0 {
    return false
  }
  let mut i = if chars[0] == '-' { 1 } else { 0 }
  let mut digits = 0
  while i < chars.length() && is_digit(chars[i]) {
    digits += 1
    i += 1
  }
  if digits == 0 {
    return false
  }
  if i < chars.length() && chars[i] == '.' {
    i += 1
    let mut frac = 0
    while i < chars.length() && is_digit(chars[i]) {
      frac += 1
      i += 1
    }
    if frac == 0 {
      return false
    }
  }
  if i < chars.length() && (chars[i] == 'e' || chars[i] == 'E') {
    i += 1
    if i < chars.length() && (chars[i] == '-' || chars[i] == '+') {
      i += 1
    }
    let mut exp = 0
    while i < chars.length() && is_digit(chars[i]) {
      exp += 1
      i += 1
    }
    if exp == 0 {
      return false
    }
  }
  i == chars.length()
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
