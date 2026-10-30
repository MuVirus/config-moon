// Blackbox tests for the xml package, against its public API.

///|
using @config {
  type StringSource,
  type Config,
  type ConfigError,
  type MemorySource,
  type Value,
}

///|
using @xml_format {type XmlFormat}

///|
/// 测试里省掉重复的 `StringSource::new(..., XmlFormat::new())`
fn xml(text : String) -> StringSource {
  StringSource::new(text, XmlFormat::new())
}

///|
/// 嵌套元素、属性和值猜类型。属性在 `@` 开头的键上。
test "xml reads nested elements, attributes and typed text" {
  let cfg = Config::new()
    .add(
      xml(
        "<config><db host=\"localhost\"><port>5432</port><ratio>0.5</ratio><on>true</on></db></config>",
      ),
    )
    .build()
  assert_eq(cfg.get_string("db.@host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 5432L)
  assert_eq(cfg.get_float("db.ratio"), 0.5)
  assert_true(cfg.get_bool("db.on"))
}

///|
/// 根元素只是壳，子元素落在顶层
test "the root element is just a shell" {
  let cfg = Config::new().add(xml("<config><a>1</a><b>2</b></config>")).build()
  assert_eq(cfg.get_int("a"), 1L)
  assert_eq(cfg.get_int("b"), 2L)
}

///|
/// 同名兄弟元素收成array
test "repeated siblings become an array" {
  let cfg = Config::new()
    .add(
      xml(
        "<config><servers><server>a</server><server>b</server></servers></config>",
      ),
    )
    .build()
  assert_eq(
    cfg.get_value("servers.server"),
    Value::array([Value::str("a"), Value::str("b")]),
  )
}

///|
/// CDATA 是字面文字，一定是字符串
test "cdata stays a string" {
  let cfg = Config::new()
    .add(
      xml(
        "<config><version><![CDATA[1.0]]></version><port><![CDATA[5432]]></port></config>",
      ),
    )
    .build()
  assert_eq(cfg.get_string("version"), "1.0")
  assert_eq(cfg.get_string("port"), "5432")
}

///|
/// 注释、声明和处理指令都被跳过
test "comments and declarations are skipped" {
  let cfg = Config::new()
    .add(
      xml(
        "<?xml version=\"1.0\"?><!-- 说明 --><?target data?><config><a>1</a></config>",
      ),
    )
    .build()
  assert_eq(cfg.get_int("a"), 1L)
}

///|
/// XML 叠在内存来源上面，只覆盖同名键
test "xml over memory overrides only the same key" {
  let cfg = Config::new()
    .add(
      MemorySource::new(
        Value::table({
          "db": Value::table({
            "host": Value::str("localhost"),
            "port": Value::int(5432L),
          }),
          "debug": Value::bool(false),
        }),
      ),
    )
    .add(xml("<config><db><port>6543</port></db></config>"))
    .build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 6543L)
  assert_false(cfg.get_bool("debug"))
}

///|
/// 空文件得到空表
test "empty xml is an empty table" {
  let cfg = Config::new().add(xml("")).build()
  let message = try {
    ignore(cfg.get_string("db.host"))
    "no error"
  } catch {
    ConfigError::MissingKey(path) => path
    e => e.to_string()
  }
  assert_eq(message, "db.host")
}

///|
/// 取值类型对不上时报 TypeMismatch
test "wrong type reports TypeMismatch" {
  let cfg = Config::new().add(xml("<config><port>5432</port></config>")).build()
  let message = try {
    ignore(cfg.get_string("port"))
    "no error"
  } catch {
    ConfigError::TypeMismatch(path, expected, actual) =>
      "\{path} \{expected} \{actual}"
    e => e.to_string()
  }
  assert_eq(message, "port Str Int")
}

///|
/// 语法错误包成 ParseError
test "malformed xml reports ParseError" {
  let message = try {
    ignore(xml("<config><a>1</config>").collect())
    "no error"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_true(message.length() > 0)
}
