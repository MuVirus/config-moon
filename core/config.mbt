///|
/// 配置：一串来源 + 一棵合并结果。
///
/// `build()` 之后来源就摊平成一棵树，取值全部走这棵树。
///
/// 这个类型不认识任何具体格式——它只认识 `Source`。
/// 想读 JSON、读文件、读环境变量，是来源包的事。
pub struct Config {
  sources : Array[&Source]
  value : Value
}

///|
/// 创建一个新的配置
pub fn Config::new() -> Config {
  { sources: [], value: Value::table(Map([], capacity=0)), }
}

///|
/// 添加一个来源，后加的优先级更高
pub fn Config::add(self : Config, source : &Source) -> Config {
  self.sources.push(source)
  self
}

///|
/// 合并所有来源（后加者优先）
pub fn Config::build(self : Config) -> Config raise ConfigError {
  { sources: [], value: self.merged(), }
}

///|
/// 当前配置对应的值：还有来源就现场合并，已经 `build` 过就直接用结果。
fn Config::merged(self : Config) -> Value raise ConfigError {
  if self.sources.is_empty() {
    return self.value
  }
  let mut acc = Value::table(Map([], capacity=8))
  for source in self.sources {
    acc = merge(acc, source.collect())
  }
  acc
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
/// 取路径上的原始值（要自己判断形状时用）
pub fn Config::get_value(
  self : Config,
  path : String,
) -> Value raise ConfigError {
  self.merged().get_path(path)
}
