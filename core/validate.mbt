///|
/// 一条校验规则：查哪个路径、怎么判断、失败报什么。
///
/// 规则只读合并后的结果，不改值；失败不自动回退，回退策略留给调用方。
/// `path` 是规则关心的位置；`check` 拿到的也是这个路径，组合规则（比如
/// `allowed_keys`）可以在它下面再拼一段。
pub struct Rule {
  priv path : KeyPath
  priv check : (KeyPath, Value) -> ConfigError?
}

///|
/// 从已经拆好的路径构造规则，给内置规则和 `custom` 共用
fn rule_at(path : KeyPath, check : (KeyPath, Value) -> ConfigError?) -> Rule {
  { path, check, }
}

///|
/// 自定义规则：返回 `None` 表示通过，`Some(实际值)` 表示失败。
///
/// `实际值` 会进错误消息，密码这类字段别原样返回，只写长度或类型。
pub fn Rule::custom(
  path : String,
  expected : String,
  check : (Value) -> String?,
) -> Rule {
  rule_at(KeyPath::parse(path), fn(found_path, value) {
    match check(value) {
      Some(actual) =>
        Some(
          ConfigError::InvalidValue(found_path.to_string(), expected, actual),
        )
      None => None
    }
  })
}

///|
/// 整数范围，两端都包含
pub fn Rule::int_range(path : String, min : Int64, max : Int64) -> Rule {
  let expected = "\{min}..\{max}"
  rule_at(KeyPath::parse(path), fn(found_path, value) {
    match value.kind {
      ValueKind::Int(number) =>
        if number < min || number > max {
          Some(
            ConfigError::InvalidValue(
              found_path.to_string(),
              expected,
              number.to_string(),
            ),
          )
        } else {
          None
        }
      kind =>
        Some(
          ConfigError::InvalidValue(
            found_path.to_string(),
            expected,
            kind.name(),
          ),
        )
    }
  })
}

///|
/// 字符串长度，两端都包含
pub fn Rule::string_len(path : String, min : Int32, max : Int32) -> Rule {
  let expected = "\{min}..\{max} characters"
  rule_at(KeyPath::parse(path), fn(found_path, value) {
    match value.kind {
      ValueKind::Str(text) => {
        let length = text.length()
        if length < min || length > max {
          Some(
            ConfigError::InvalidValue(
              found_path.to_string(),
              expected,
              "\{length} characters",
            ),
          )
        } else {
          None
        }
      }
      kind =>
        Some(
          ConfigError::InvalidValue(
            found_path.to_string(),
            expected,
            kind.name(),
          ),
        )
    }
  })
}

///|
/// 只接受列表里的字符串
pub fn Rule::one_of(path : String, allowed : Array[String]) -> Rule {
  let expected = allowed.join(" / ")
  rule_at(KeyPath::parse(path), fn(found_path, value) {
    match value.kind {
      ValueKind::Str(text) =>
        if allowed.contains(text) {
          None
        } else {
          Some(
            ConfigError::InvalidValue(found_path.to_string(), expected, text),
          )
        }
      kind =>
        Some(
          ConfigError::InvalidValue(
            found_path.to_string(),
            expected,
            kind.name(),
          ),
        )
    }
  })
}

///|
/// 这一层只允许出现列表里的键；多出来的键报 `UnknownKey`，路径指到具体的键。
///
/// `derive(FromJson)` 会忽略结构体里没有的字段，所以未知键只能这样按路径查，
/// 不写这条规则就不查。
pub fn Rule::allowed_keys(path : String, allowed : Array[String]) -> Rule {
  rule_at(KeyPath::parse(path), fn(found_path, value) {
    match value.kind {
      ValueKind::Table(table) => {
        for key, _ in table {
          if !allowed.contains(key) {
            return Some(
              ConfigError::UnknownKey(found_path.add(key).to_string()),
            )
          }
        }
        None
      }
      kind =>
        Some(
          ConfigError::TypeMismatch(
            found_path.to_string(),
            "Table",
            kind.name(),
          ),
        )
    }
  })
}

///|
/// 检查一个整数是否落在范围内，给 `Validate` 实现用
pub fn check_int_range(
  path : KeyPath,
  value : Int64,
  min : Int64,
  max : Int64,
) -> Unit raise ConfigError {
  if value < min || value > max {
    raise ConfigError::InvalidValue(
      path.to_string(),
      "\{min}..\{max}",
      value.to_string(),
    )
  }
}

///|
/// 检查字符串长度，给 `Validate` 实现用
pub fn check_string_len(
  path : KeyPath,
  value : String,
  min : Int32,
  max : Int32,
) -> Unit raise ConfigError {
  let length = value.length()
  if length < min || length > max {
    raise ConfigError::InvalidValue(
      path.to_string(),
      "\{min}..\{max} characters",
      "\{length} characters",
    )
  }
}

///|
/// 结构体自己的约束：提取后立刻跑，`prefix` 是提取时的起始路径。
///
/// 字段改了，约束跟着改，不用在别处再维护一份路径字符串。
pub(open) trait Validate {
  fn validate(Self, KeyPath) -> Unit raise ConfigError
}

///|
/// 按键校验：遇到第一个错误就停
pub fn Config::validate(
  self : Config,
  rules : Array[Rule],
) -> Unit raise ConfigError {
  let value = self.merged()
  for rule in rules {
    match check_rule(value, rule) {
      Some(error) => raise error
      None => ()
    }
  }
}

///|
/// 按键校验：一次列出全部问题，顺序和规则表一致
pub fn Config::validate_all(
  self : Config,
  rules : Array[Rule],
) -> Array[ConfigError] raise ConfigError {
  let value = self.merged()
  let errors : Array[ConfigError] = []
  for rule in rules {
    match check_rule(value, rule) {
      Some(error) => errors.push(error)
      None => ()
    }
  }
  errors
}

///|
/// 取路径、跑检查；路径本身不存在时直接报 `MissingKey`
fn check_rule(value : Value, rule : Rule) -> ConfigError? {
  let found = value.get_at(rule.path) catch { error => return Some(error) }
  (rule.check)(rule.path, found)
}
