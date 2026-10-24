///|
/// 合并规则。
///
/// 规则是整份 `Config` 的，不做单层特殊；要单层特殊就给 `Source` 包一层。
pub(all) enum MergeRule {
  /// 后加的覆盖先加的（默认）
  LastWins
  /// 先加的赢，后加的只补空缺
  FirstWins
  /// 按 `SourceKind` 排序，数组里越靠前的优先级越高；没列出的排在最后。
  /// 同一档内仍是后加的赢。
  ByKind(Array[SourceKind])
  /// 自己合：参数是「已经合好的部分」和「下一层」，返回值成为新的部分。
  /// 来源信息已经挂在 `Value` 上，自定义函数要自己负责保留。
  Custom((Value, Value) -> Value)
}

///|
/// 一个 kind 在 `ByKind` 里的优先级，数字越小越优先。
fn kind_rank(kind : SourceKind, order : Array[SourceKind]) -> Int32 {
  for i, candidate in order {
    if candidate == kind {
      return i
    }
  }
  order.length()
}
