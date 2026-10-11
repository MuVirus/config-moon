///|
/// 配置值在内存里的形状。
///
/// 整数一律 `Int64`：中间表示不走浮点，大整数才能原样活到用户手上。
pub(all) enum ValueKind {
  Null
  Bool(Bool)
  Int(Int64)
  Float(Double)
  Str(String)
  Array(Array[Value])
  Table(Map[String, Value])
} derive(Eq, @debug.Debug)

///|
/// 配置值。
///
/// 包一层壳而不是直接用 `ValueKind`，是为了以后加字段时不用改所有构造点。
pub struct Value {
  kind : ValueKind
} derive(Eq, @debug.Debug)

///|
/// 空值
pub fn Value::null() -> Value {
  { kind: ValueKind::Null, }
}

///|
/// 布尔
pub fn Value::bool(b : Bool) -> Value {
  { kind: ValueKind::Bool(b), }
}

///|
/// 整数
pub fn Value::int(i : Int64) -> Value {
  { kind: ValueKind::Int(i), }
}

///|
/// 浮点数
pub fn Value::float(f : Double) -> Value {
  { kind: ValueKind::Float(f), }
}

///|
/// 字符串
pub fn Value::str(s : String) -> Value {
  { kind: ValueKind::Str(s), }
}

///|
/// 数组
pub fn Value::array(arr : Array[Value]) -> Value {
  { kind: ValueKind::Array(arr), }
}

///|
/// 表
pub fn Value::table(tbl : Map[String, Value]) -> Value {
  { kind: ValueKind::Table(tbl), }
}

///|
/// `derive` 生成的 `impl` 不再自动变成方法，需要显式挂上去。
pub extend Value with Eq::{equal, not_equal}

///|
pub extend Value with @debug.Debug::{to_repr}

///|
pub extend ValueKind with Eq::{equal, not_equal}

///|
pub extend ValueKind with @debug.Debug::{to_repr}

///|
/// 形状的名字，报错时用（"期望 Int，实际 Str" 里的那两个词）
pub fn ValueKind::name(self : ValueKind) -> String {
  match self {
    ValueKind::Null => "Null"
    ValueKind::Bool(_) => "Bool"
    ValueKind::Int(_) => "Int"
    ValueKind::Float(_) => "Float"
    ValueKind::Str(_) => "Str"
    ValueKind::Array(_) => "Array"
    ValueKind::Table(_) => "Table"
  }
}
