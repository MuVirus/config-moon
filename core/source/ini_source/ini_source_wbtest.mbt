// Whitebox tests for the ini package: the parser's edges all live here.

///|
using @config {type ConfigError, type Value}

///|
/// `;` 和 `#` 都在整行开头才算注释，行尾的 `#` 属于值
test "comments only at line start" {
  let v = parse_ini("; 注释\n# 也是注释\ncolor = #ff0000\n")
  assert_eq(v, Value::table({ "color": Value::str("#ff0000") }))
}

///|
test "blank lines and indentation are ignored" {
  let v = parse_ini("\n\n   [db]  \n\t host = localhost \n\n")
  assert_eq(
    v,
    Value::table({ "db": Value::table({ "host": Value::str("localhost") }) }),
  )
}

///|
/// `:` 也能当分隔符
test "colon works as delimiter" {
  let v = parse_ini("[db]\nhost : localhost\n")
  assert_eq(
    v,
    Value::table({ "db": Value::table({ "host": Value::str("localhost") }) }),
  )
}

///|
/// 大整数不丢
test "big integers survive" {
  let v = parse_ini("id = 9007199254740993\n")
  assert_eq(v, Value::table({ "id": Value::int(9007199254740993L) }))
}

///|
/// 整数溢出 Int64 报错，不静默截断
test "integer overflow reports ParseError" {
  let message = try {
    ignore(parse_ini("id = 99999999999999999999\n"))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(
    message, "第 1 行：整数 99999999999999999999 超出 Int64 范围",
  )
}

///|
/// 浮点的几种写法
test "float shapes" {
  let v = parse_ini("a = 1.5\nb = -0.5\nc = 1.5e3\nd = 2E-2\n")
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
  let v = parse_ini("a = 1.\nb = .5\nc = 1.2.3\nd = 1e\ne = -\nf = 12abc\n")
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
/// 只有 `true` / `false` 是布尔，其它拼法都按字符串
test "only true and false are booleans" {
  let v = parse_ini("a = true\nb = TRUE\nc = yes\nd = false\n")
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
/// 空值是空字符串，不是 Null
test "empty value is an empty string" {
  let v = parse_ini("a =\n")
  assert_eq(v, Value::table({ "a": Value::str("") }))
}

///|
/// 重复段落和重复键都是后写的赢
test "duplicates: later wins" {
  let v = parse_ini("[db]\nport = 1\nhost = a\n[db]\nport = 2\n")
  assert_eq(
    v,
    Value::table({
      "db": Value::table({ "port": Value::int(2L), "host": Value::str("a") }),
    }),
  )
}

///|
/// 空段落不产生键
test "empty section produces nothing" {
  let v = parse_ini("[db]\n[cache]\n")
  assert_eq(v, Value::table({}))
}

///|
/// 段落名里的点拆成多层
test "dotted section nests" {
  let v = parse_ini("[a.b.c]\nk = 1\n")
  assert_eq(
    v,
    Value::table({
      "a": Value::table({
        "b": Value::table({ "c": Value::table({ "k": Value::int(1L) }) }),
      }),
    }),
  )
}

///|
/// 已经是标量的名字又被当段落用，报错说清楚
test "section shadowing a scalar reports ParseError" {
  let message = try {
    ignore(parse_ini("a = 1\n[a]\nb = 2\n"))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "第 2 行：a 已经是 Int，不能当段落名")
}

///|
test "missing delimiter reports ParseError" {
  let message = try {
    ignore(parse_ini("[db]\nhost\n"))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "第 2 行：host 缺 `=` 或 `:`")
}

///|
test "empty key reports ParseError" {
  let message = try {
    ignore(parse_ini("[db]\n = localhost\n"))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "第 2 行：键名为空")
}

///|
test "unclosed section header reports ParseError" {
  let message = try {
    ignore(parse_ini("[db\nport = 1\n"))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "第 1 行：段落头 [db 缺右方括号")
}

///|
test "empty section name reports ParseError" {
  let message = try {
    ignore(parse_ini("[]\nport = 1\n"))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "第 1 行：段落名  有空的一层")
}

///|
test "empty section layer reports ParseError" {
  let message = try {
    ignore(parse_ini("[a..b]\nk = 1\n"))
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "第 1 行：段落名 a..b 有空的一层")
}

///|
/// CRLF 文件也能读
test "crlf line endings" {
  let v = parse_ini("[db]\r\nport = 5432\r\n")
  assert_eq(
    v,
    Value::table({ "db": Value::table({ "port": Value::int(5432L) }) }),
  )
}

///|
test "last line without newline" {
  let v = parse_ini("[db]\nport = 5432")
  assert_eq(
    v,
    Value::table({ "db": Value::table({ "port": Value::int(5432L) }) }),
  )
}
