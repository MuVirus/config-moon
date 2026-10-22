// Blackbox tests for the cbor package, against its public API.

///|
using @config {type Config, type ConfigError, type MemorySource, type Value}

///|
using @cbor_source {type CborSource}

///|
/// 嵌套的映射
test "cbor reads a nested map" {
  let cfg = Config::new()
    .add(
      CborSource::from_bytes(
        b"\xa1\x62db\xa2\x64host\x69localhost\x64port\x19\x15\x38",
      ),
    )
    .build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 5432L)
}

///|
/// 各种标量
test "cbor reads every scalar kind" {
  let cfg = Config::new()
    .add(
      CborSource::from_bytes(
        b"\xa7\x61i\x18\x2a\x61f\xfb\x3f\xf8\x00\x00\x00\x00\x00\x00\x61s\x62hi\x61b\xf5\x61n\xf6\x63arr\x82\x01\x02\x61m\xa1\x61k\x61v",
      ),
    )
    .build()
  assert_eq(cfg.get_int("i"), 42L)
  assert_eq(cfg.get_float("f"), 1.5)
  assert_eq(cfg.get_string("s"), "hi")
  assert_true(cfg.get_bool("b"))
  assert_eq(cfg.get_value("n"), Value::null())
  assert_eq(
    cfg.get_value("arr"),
    Value::array([Value::int(1L), Value::int(2L)]),
  )
  assert_eq(cfg.get_value("m"), Value::table({ "k": Value::str("v") }))
}

///|
/// 负整数
test "cbor reads negative integers" {
  let cfg = Config::new().add(CborSource::from_bytes(b"\xa1\x61n\x20")).build()
  assert_eq(cfg.get_int("n"), -1L)
}

///|
/// 字节串原样保留
test "cbor keeps byte strings as bytes" {
  let cfg = Config::new()
    .add(CborSource::from_bytes(b"\xa1\x64blob\x43\x01\x02\xff"))
    .build()
  assert_eq(cfg.get_bytes("blob"), b"\x01\x02\xff")
  assert_eq(cfg.get_value("blob"), Value::bytes(b"\x01\x02\xff"))
}

///|
/// 标签被剥掉，只留里面的值
test "cbor strips tags" {
  // {"0": 0("2020-01-01")}
  let cfg = Config::new()
    .add(CborSource::from_bytes(b"\xa1\x610\xc0\x6a2020-01-01"))
    .build()
  assert_eq(cfg.get_string("0"), "2020-01-01")
}

///|
/// 半精度和单精度浮点都展宽到 Double
test "cbor widens narrow floats" {
  let half = Config::new()
    .add(CborSource::from_bytes(b"\xa1\x61h\xf9\x3e\x00"))
    .build()
  let single = Config::new()
    .add(CborSource::from_bytes(b"\xa1\x61s\xfa\x3f\xc0\x00\x00"))
    .build()
  assert_eq(half.get_float("h"), 1.5)
  assert_eq(single.get_float("s"), 1.5)
}

///|
/// 不定长容器也能读
test "cbor reads indefinite-length containers" {
  // {"t": (_ "hi")}
  let cfg = Config::new()
    .add(CborSource::from_bytes(b"\xa1\x61t\x7f\x62hi\xff"))
    .build()
  assert_eq(cfg.get_string("t"), "hi")
}

///|
/// 大整数在 Int64 范围内时原样保留
test "big integers inside Int64 survive" {
  let cfg = Config::new()
    .add(
      CborSource::from_bytes(b"\xa1\x63big\x1b\x00\x20\x00\x00\x00\x00\x00\x01"),
    )
    .build()
  assert_eq(cfg.get_int("big"), 9007199254740993L)
}

///|
/// CBOR 叠在内存来源上面，只覆盖同名键
test "cbor over memory overrides only the same key" {
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
    .add(CborSource::from_bytes(b"\xa1\x62db\xa1\x64port\x19\x19\x8f"))
    .build()
  assert_eq(cfg.get_string("db.host"), "localhost")
  assert_eq(cfg.get_int("db.port"), 6543L)
  assert_false(cfg.get_bool("debug"))
}

///|
/// 根节点不是映射时报 ParseError
test "non-map root reports ParseError" {
  let message = try {
    ignore(CborSource::from_bytes(b"\x82\x01\x02").collect())
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "CBOR 的根节点必须是映射，实际是 数组")
}

///|
/// 映射键不是文本字符串时报 ParseError
test "non-string map key reports ParseError" {
  let message = try {
    ignore(CborSource::from_bytes(b"\xa1\x01\x61x").collect())
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(
    message, "CBOR 的映射键必须是文本字符串，实际是 整数",
  )
}

///|
/// undefined 报错，不悄悄当成空值
test "undefined reports ParseError" {
  let message = try {
    ignore(CborSource::from_bytes(b"\xa1\x61u\xf7").collect())
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "CBOR 的 undefined 在 Value 里没有对应形状")
}

///|
/// 整数超出 Int64 范围时报 ParseError
test "integer beyond Int64 reports ParseError" {
  let message = try {
    ignore(
      CborSource::from_bytes(b"\xa1\x63big\x1b\xff\xff\xff\xff\xff\xff\xff\xff").collect(),
    )
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "整数 18446744073709551615 超出 Int64 范围")
}

///|
/// 末尾有多余字节时报 ParseError
test "trailing bytes report ParseError" {
  let message = try {
    ignore(CborSource::from_bytes(b"\xf6\x00").collect())
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "数据末尾还有 1 个字节没读完")
}

///|
/// 数据不完整时报 ParseError
test "truncated input reports ParseError" {
  let message = try {
    ignore(CborSource::from_bytes(b"\xa1\x64port\x19\x15").collect())
    "没有报错"
  } catch {
    ConfigError::ParseError(m) => m
    e => e.to_string()
  }
  assert_eq(message, "数据意外结束")
}

///|
/// 取值类型对不上时报 TypeMismatch
test "wrong type reports TypeMismatch" {
  let cfg = Config::new()
    .add(CborSource::from_bytes(b"\xa1\x64port\x19\x15\x38"))
    .build()
  let message = try {
    ignore(cfg.get_string("port"))
    "没有报错"
  } catch {
    ConfigError::TypeMismatch(path, expected, actual) =>
      "\{path} \{expected} \{actual}"
    e => e.to_string()
  }
  assert_eq(message, "port Str Int")
}

///|
/// 对字节串取字符串会报出实际类型
test "bytes report Bytes as the actual type" {
  let cfg = Config::new()
    .add(CborSource::from_bytes(b"\xa1\x64blob\x43\x01\x02\xff"))
    .build()
  let message = try {
    ignore(cfg.get_string("blob"))
    "没有报错"
  } catch {
    ConfigError::TypeMismatch(path, expected, actual) =>
      "\{path} \{expected} \{actual}"
    e => e.to_string()
  }
  assert_eq(message, "blob Str Bytes")
}
