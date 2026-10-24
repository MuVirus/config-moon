///|
/// 来源的大类。
///
/// 合并规则按它排序，展示和错误消息也用它。具体是哪个文件、哪个环境变量，
/// 由 `Origin::label` 说明；`label` 只给人看，不参与判断。
pub(all) enum SourceKind {
  Memory
  File
  Env
  Cli
  Custom
} derive(Eq, @debug.Debug)

///|
pub extend SourceKind with Eq::{equal, not_equal}

///|
pub extend SourceKind with @debug.Debug::{to_repr}

///|
/// 能反推出原始字节的对象。
///
/// `FileSource` 用平台自己的路径或 URL 实现它，core 只看到 `read()`。
/// 现在还没有实现：只有内存来源时没有可反推的对象，等 `FileSource` 落地再填。
pub(open) trait Locator {
  fn read(Self) -> Bytes raise ConfigError
}

///|
/// 一个值的来源。
///
/// `kind` 用来分支和排序，`label` 只用于展示，`locator` 能反推时才给。
/// 表节点的来源是「最后碰它的那层」，只有叶子路径的来源准确。
pub(all) struct Origin {
  kind : SourceKind
  label : String
  locator : &Locator?
}

///|
/// 构造一个没有 locator 的来源信息
pub fn Origin::new(kind : SourceKind, label : String) -> Origin {
  { kind, label, locator: None, }
}
