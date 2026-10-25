///|
/// 配置值在内存里的形状。
///
/// 整数一律 `Int64`：中间表示不走浮点，大整数才能原样活到用户手上。
///
/// `Bytes` 是二进制数据的形状。文本格式不会产生它，CBOR 这类二进制格式会。
pub(all) enum ValueKind {
  Null
  Bool(Bool)
  Int(Int64)
  Float(Double)
  Str(String)
  Bytes(Bytes)
  Array(Array[Value])
  Table(Map[String, Value])
} derive(Eq, @debug.Debug)

///|
/// 配置值。
///
/// 包一层壳而不是直接用 `ValueKind`，是为了以后加字段时不用改所有构造点。
///
/// `origin` 指向这层来源的对象；构造器一律给 `None`，由 `Config` 在合并前补上。
/// 它不参与相等比较，否则内容相同、来源不同的两个值会不相等。
pub struct Value {
  kind : ValueKind
  priv origin : &OriginSite?
}

///|
/// 空值
pub fn Value::null() -> Value {
  { kind: ValueKind::Null, origin: None, }
}

///|
/// 布尔
pub fn Value::bool(b : Bool) -> Value {
  { kind: ValueKind::Bool(b), origin: None, }
}

///|
/// 整数
pub fn Value::int(i : Int64) -> Value {
  { kind: ValueKind::Int(i), origin: None, }
}

///|
/// 浮点数
pub fn Value::float(f : Double) -> Value {
  { kind: ValueKind::Float(f), origin: None, }
}

///|
/// 字符串
pub fn Value::str(s : String) -> Value {
  { kind: ValueKind::Str(s), origin: None, }
}

///|
/// 字节串
pub fn Value::bytes(b : Bytes) -> Value {
  { kind: ValueKind::Bytes(b), origin: None, }
}

///|
/// 数组
pub fn Value::array(arr : Array[Value]) -> Value {
  { kind: ValueKind::Array(arr), origin: None, }
}

///|
/// 表
pub fn Value::table(tbl : Map[String, Value]) -> Value {
  { kind: ValueKind::Table(tbl), origin: None, }
}

///|
/// 给一个值挂上来源。
///
/// `Config` 合并前会给来源产出的整棵树补来源；组合来源（比如一个来源里读多个文件）
/// 可以先用这个函数给子树标上各自的 site，`Config` 不会覆盖已有的。
///
/// 传进来的 site 不要持有这棵值树：native 默认的引用计数不回收环，
/// `site → 值树 → &site` 会漏。
pub fn Value::with_origin(self : Value, origin : &OriginSite) -> Value {
  { kind: self.kind, origin: Some(origin), }
}

///|
/// 只比 `kind`：来源不同不算值不同。
pub impl Eq for Value with fn equal(self : Value, other : Value) -> Bool {
  self.kind == other.kind
}

///|
/// `derive` 生成的 `impl` 不再自动变成方法，需要显式挂上去。
pub extend Value with Eq::{equal, not_equal}

///|
/// 调试输出只看形状，不把来源混进来。
pub impl @debug.Debug for Value with fn to_repr(self : Value) -> @debug.Repr {
  self.kind.to_repr()
}

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
    ValueKind::Bytes(_) => "Bytes"
    ValueKind::Array(_) => "Array"
    ValueKind::Table(_) => "Table"
  }
}
