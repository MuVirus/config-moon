///|
/// 配置：一串来源、一条合并规则、一棵合并结果。
///
/// `build()` 之后来源就摊平成一棵树，取值全部走这棵树。
///
/// 这个类型不认识任何具体格式——它只认识 `Source`。
/// 想读 JSON、读文件、读环境变量，是来源包的事。
pub struct Config {
  sources : Array[&Source]
  rule : MergeRule
  value : Value
}

///|
/// 创建一个新的配置，默认后加者优先
pub fn Config::new() -> Config {
  {
    sources: [],
    rule: MergeRule::LastWins,
    value: Value::table(Map([], capacity=0)),
  }
}

///|
/// 添加一个来源
pub fn Config::add(self : Config, source : &Source) -> Config {
  self.sources.push(source)
  self
}

///|
/// 换一条合并规则
pub fn Config::with_rule(self : Config, rule : MergeRule) -> Config {
  { sources: self.sources, rule, value: self.value, }
}

///|
/// 按规则合并所有来源
pub fn Config::build(self : Config) -> Config raise ConfigError {
  { sources: [], rule: self.rule, value: self.merged(), }
}

///|
/// 当前配置对应的值：还有来源就现场合并，已经 `build` 过就直接用结果。
fn Config::merged(self : Config) -> Value raise ConfigError {
  if self.sources.is_empty() {
    return self.value
  }
  let ordered = self.ordered_sources()
  let rule = self.rule
  let mut acc : Value? = None
  for source in ordered {
    let layer = attach_origin(source.collect(), source.origin())
    acc = Some(
      match acc {
        None => layer
        Some(base) =>
          match rule {
            MergeRule::Custom(custom) => custom(base, layer)
            _ => merge(base, layer)
          }
      },
    )
  }
  acc.unwrap_or(Value::table(Map([], capacity=0)))
}

///|
/// 按合并规则决定来源的处理顺序；后面处理的优先级更高。
fn Config::ordered_sources(self : Config) -> Array[&Source] {
  let rule = self.rule
  match rule {
    MergeRule::FirstWins => self.sources.rev()
    MergeRule::ByKind(order) => {
      let keyed : Array[(Int32, Int32, &Source)] = []
      for i, source in self.sources {
        let kind = match source.origin() {
          Some(origin) => origin.kind
          None => SourceKind::Custom
        }
        keyed.push((kind_rank(kind, order), i, source))
      }
      keyed.sort_by(fn(a, b) {
        if a.0 != b.0 {
          b.0.compare(a.0)
        } else {
          a.1.compare(b.1)
        }
      })
      keyed.map(fn(entry) { entry.2 })
    }
    _ => self.sources
  }
}

///|
/// 给整棵树补上来源；表节点和数组节点也带上，叶子才有意义。
fn attach_origin(value : Value, origin : Origin?) -> Value {
  match origin {
    None => value
    Some(_) =>
      match value.kind {
        ValueKind::Table(table) => {
          let mapped : Map[String, Value] = Map([], capacity=table.capacity())
          for key, child in table {
            mapped[key] = attach_origin(child, origin)
          }
          { kind: ValueKind::Table(mapped), origin, }
        }
        ValueKind::Array(array) =>
          {
            kind: ValueKind::Array(
              array.map(fn(child) { attach_origin(child, origin) }),
            ),
            origin,
          }
        kind => { kind, origin, }
      }
  }
}

///|
/// 取路径上的字符串
pub fn Config::get_string(
  self : Config,
  path : String,
) -> String raise ConfigError {
  let value = self.get_value(path)
  match value.kind {
    ValueKind::Str(s) => s
    k => raise ConfigError::TypeMismatch(path, "Str", k.name())
  }
}

///|
/// 取路径上的整数（`Int64`，大整数不丢）
pub fn Config::get_int(self : Config, path : String) -> Int64 raise ConfigError {
  let value = self.get_value(path)
  match value.kind {
    ValueKind::Int(i) => i
    k => raise ConfigError::TypeMismatch(path, "Int", k.name())
  }
}

///|
/// 取路径上的布尔
pub fn Config::get_bool(self : Config, path : String) -> Bool raise ConfigError {
  let value = self.get_value(path)
  match value.kind {
    ValueKind::Bool(b) => b
    k => raise ConfigError::TypeMismatch(path, "Bool", k.name())
  }
}

///|
/// 取路径上的浮点数
pub fn Config::get_float(
  self : Config,
  path : String,
) -> Double raise ConfigError {
  let value = self.get_value(path)
  match value.kind {
    ValueKind::Float(f) => f
    k => raise ConfigError::TypeMismatch(path, "Float", k.name())
  }
}

///|
/// 取路径上的字节串
pub fn Config::get_bytes(
  self : Config,
  path : String,
) -> Bytes raise ConfigError {
  let value = self.get_value(path)
  match value.kind {
    ValueKind::Bytes(b) => b
    k => raise ConfigError::TypeMismatch(path, "Bytes", k.name())
  }
}

///|
/// 取路径上的原始值（要自己判断形状时用）
pub fn Config::get_value(
  self : Config,
  path : String,
) -> Value raise ConfigError {
  self.merged().get_path(path)
}

///|
/// 某个路径最终来自哪一层。路径不存在时给 `None`。
pub fn Config::origin_of(
  self : Config,
  path : String,
) -> Origin? raise ConfigError {
  let value = self.get_value(path) catch {
    ConfigError::MissingKey(_) | ConfigError::TypeMismatch(_, _, _) =>
      return None
    error => raise error
  }
  value.origin
}

///|
/// 所有叶子路径和它们的来源，适合做 `--print-config` 这类诊断命令。
pub fn Config::origins(
  self : Config,
) -> Array[(String, Origin)] raise ConfigError {
  let result : Array[(String, Origin)] = []
  collect_origins(self.merged(), "", result)
  result
}

///|
fn collect_origins(
  value : Value,
  prefix : String,
  result : Array[(String, Origin)],
) -> Unit {
  match value.kind {
    ValueKind::Table(table) =>
      for key, child in table {
        let path = if prefix == "" { key } else { "\{prefix}.\{key}" }
        collect_origins(child, path, result)
      }
    _ =>
      match value.origin {
        Some(origin) => result.push((prefix, origin))
        None => ()
      }
  }
}
