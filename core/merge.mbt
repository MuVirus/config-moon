///|
/// 合并两条规则：两边都是表就逐 key 合，其它情况后加的赢。
///
/// - 都是 `Table` → 递归逐 key 合并，表节点取 `over` 的 origin
/// - 其它 → `over` 覆盖 `base`
/// - 数组**整体替换**，不拼接
fn merge(base : Value, over : Value) -> Value {
  match (base.kind, over.kind) {
    (ValueKind::Table(a), ValueKind::Table(b)) =>
      { kind: ValueKind::Table(merge_table(a, b)), origin: over.origin, }
    _ => over
  }
}

///|
/// 逐 key 合并两张表：b 的 key 赢，两边都是表时继续往下合。
fn merge_table(
  base : Map[String, Value],
  over : Map[String, Value],
) -> Map[String, Value] {
  let result = base.copy()
  for key, over_value in over {
    result[key] = match result.get(key) {
      Some(base_value) => merge(base_value, over_value)
      None => over_value
    }
  }
  result
}
