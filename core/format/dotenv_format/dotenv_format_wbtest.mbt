// Whitebox tests for the dotenv package: the parser's edges all live here.

///|
using @config {type ConfigError, type Value}

///|
/// 整行注释、空行、缩进都不产生键
test "comments, blank lines and indentation" {
  let v = parse_dotenv(
    "# 注释\n\n   # 缩进的注释\n  DB_HOST = localhost  \n",
  )
  assert_eq(v, Value::table({ "DB_HOST": Value::str("localhost") }))
}

///|
/// 行尾 `#` 前面有空白才算注释
test "inline comments need whitespace before the hash" {
  let v = parse_dotenv(
    "a = value # 注释\nb = value#不是注释\nc=#ff0000\nd = # 注释\n",
  )
  assert_eq(
    v,
    Value::table({
      "a": Value::str("value"),
      "b": Value::str("value#不是注释"),
      "c": Value::str("#ff0000"),
      "d": Value::str(""),
    }),
  )
}

///|
/// 单引号原样保留，双引号认转义
test "quotes and escapes" {
  let v = parse_dotenv(
    "a = 'no \\n escape'\nb = \"line\\nnext\"\nc = \"tab\\there\"\nd = \"quote\\\"inside\"\ne = \"C:\\path\\zoo\"\nf = 'a\\b'\n",
  )
  assert_eq(
    v,
    Value::table({
      "a": Value::str("no \\n escape"),
      "b": Value::str("line\nnext"),
      "c": Value::str("tab\there"),
      "d": Value::str("quote\"inside"),
      "e": Value::str("C:\\path\\zoo"),
      "f": Value::str("a\\b"),
    }),
  )
}

///|
/// 引号后面的空白和注释可以忽略
test "trailing comment after quoted value" {
  let v = parse_dotenv("a = \"value\" # 注释\nb = 'value'#注释\n")
  assert_eq(
    v,
    Value::table({ "a": Value::str("value"), "b": Value::str("value") }),
  )
}

///|
/// 引号结束后还有别的内容，报错说清楚
test "junk after quoted value reports ParseError" {
  let message = try {
    ignore(parse_dotenv("a = \"value\" junk\n"))
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "line 1: unexpected content after closing quote: junk")
}

///|
/// 引号没闭合报错
test "unterminated quote reports ParseError" {
  let message = try {
    ignore(parse_dotenv("a = \"value\n"))
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "line 1: unterminated double quote")
}

///|
/// `export` 前缀，空格和 tab 都能跟
test "export prefix" {
  let v = parse_dotenv("export a=1\nexport\tb=2\nexport   c=3\n")
  assert_eq(
    v,
    Value::table({
      "a": Value::int(1L),
      "b": Value::int(2L),
      "c": Value::int(3L),
    }),
  )
}

///|
/// 光有 export 没有键值对报错
test "bare export reports ParseError" {
  let message = try {
    ignore(parse_dotenv("export\n"))
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "line 1: export is missing a key-value pair")
}

///|
/// 大integer不丢
test "big integers survive" {
  let v = parse_dotenv("id = 9007199254740993\n")
  assert_eq(v, Value::table({ "id": Value::int(9007199254740993L) }))
}

///|
/// integer溢出 Int64 报错，不静默截断
test "integer overflow reports ParseError" {
  let message = try {
    ignore(parse_dotenv("id = 99999999999999999999\n"))
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "line 1: integer 99999999999999999999 exceeds Int64 range")
}

///|
/// 浮点的几种写法
test "float shapes" {
  let v = parse_dotenv("a = 1.5\nb = -0.5\nc = 1.5e3\nd = 2E-2\n")
  assert_eq(
    v,
    Value::table({
      "a": Value::float(1.5),
      "b": Value::float(-0.5),
      "c": Value::float(1500.0),
      "d": Value::float(0.02),
    }),
  )
}

///|
/// 像数字但不是数字的东西一律当字符串
test "number-ish strings stay strings" {
  let v = parse_dotenv("a = 1.\nb = .5\nc = 1.2.3\nd = 1e\ne = -\nf = 12abc\n")
  assert_eq(
    v,
    Value::table({
      "a": Value::str("1."),
      "b": Value::str(".5"),
      "c": Value::str("1.2.3"),
      "d": Value::str("1e"),
      "e": Value::str("-"),
      "f": Value::str("12abc"),
    }),
  )
}

///|
/// 只有 `true` / `false` 是boolean，其它拼法都按字符串
test "only true and false are booleans" {
  let v = parse_dotenv("a = true\nb = TRUE\nc = yes\nd = false\n")
  assert_eq(
    v,
    Value::table({
      "a": Value::bool(true),
      "b": Value::str("TRUE"),
      "c": Value::str("yes"),
      "d": Value::bool(false),
    }),
  )
}

///|
/// null是empty string，不是 Null
test "empty value is an empty string" {
  let v = parse_dotenv("a =\nb = \"\"\n")
  assert_eq(v, Value::table({ "a": Value::str(""), "b": Value::str("") }))
}

///|
/// 重复键后写的赢
test "duplicate keys: later wins" {
  let v = parse_dotenv("a = 1\nb = 2\na = 3\n")
  assert_eq(v, Value::table({ "a": Value::int(3L), "b": Value::int(2L) }))
}

///|
/// 键名里的点拆成多层
test "dotted keys nest" {
  let v = parse_dotenv("a.b.c = 1\n")
  assert_eq(
    v,
    Value::table({
      "a": Value::table({ "b": Value::table({ "c": Value::int(1L) }) }),
    }),
  )
}

///|
/// 标量先占名字，后面又当层级用，报错说清楚
test "scalar shadowed by nesting reports ParseError" {
  let message = try {
    ignore(parse_dotenv("a = 1\na.b = 2\n"))
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(
    message, "line 2: a is already Int and cannot be used as a path segment",
  )
}

///|
/// 反过来，后写的标量整体覆盖先写的表
test "scalar replaces an earlier table" {
  let v = parse_dotenv("a.b = 1\na = 2\n")
  assert_eq(v, Value::table({ "a": Value::int(2L) }))
}

///|
/// 键名的空层报错
test "empty key layer reports ParseError" {
  let message = try {
    ignore(parse_dotenv("a..b = 1\n"))
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "line 1: key a..b has an empty segment")
}

///|
/// 键名里有空白报错
test "whitespace in key reports ParseError" {
  let message = try {
    ignore(parse_dotenv("a b = 1\n"))
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "line 1: key a b contains whitespace")
}

///|
test "missing equals reports ParseError" {
  let message = try {
    ignore(parse_dotenv("a\n"))
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "line 1: a is missing '='")
}

///|
test "empty key reports ParseError" {
  let message = try {
    ignore(parse_dotenv(" = value\n"))
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "line 1: key name is empty")
}

///|
/// CRLF 文件也能读
test "crlf line endings" {
  let v = parse_dotenv("a=1\r\nb=two\r\n")
  assert_eq(v, Value::table({ "a": Value::int(1L), "b": Value::str("two") }))
}

///|
test "last line without newline" {
  let v = parse_dotenv("a=1")
  assert_eq(v, Value::table({ "a": Value::int(1L) }))
}

///|
/// 带 BOM 的文件也能读
test "utf-8 bom is ignored" {
  let v = parse_dotenv("\u{FEFF}a=1\n")
  assert_eq(v, Value::table({ "a": Value::int(1L) }))
}
