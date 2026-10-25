///|
/// 来源的大类。
///
/// 合并规则按它排序，展示和错误消息也用它。具体是哪个文件、哪个环境变量，
/// 由 `OriginSite::describe` 说明；`describe` 只给人看，不参与判断。
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
/// `FileSource` 用字符串路径实现它，core 只看到 `read()`。
pub(open) trait Locator {
  fn read(Self) -> Bytes raise ConfigError
}

///|
/// 一个值的来源对象。
///
/// 追踪信息只存这个对象的引用，真正的内容留在来源自己手里：文件路径、环境变量名、
/// 命令行参数名。`describe` 在展示时才拼出 `env:APP_DB_PORT` 这样的字符串，
/// 所以 `Value` 上不存格式化好的 label。
///
/// `describe` 拿到键路径：环境变量和命令行靠它找到具体是哪个变量或参数；
/// 文件只关心文件本身，可以忽略路径。
pub(open) trait OriginSite {
  /// 来源的大类
  fn kind(Self) -> SourceKind
  /// 展示用的来源描述，例如 `file:config/app.json`
  fn describe(Self, KeyPath) -> String
  /// 能反推原始字节时才给
  fn locator(Self) -> &Locator? = _
}

///|
/// 默认没有可反推的内容
impl OriginSite with fn locator(_) {
  None
}

///|
/// 一个键的完整来源：来源对象 + 层级路径。
///
/// `path` 是查询时算出来的，不在 `Value` 上存；`label` 也是按需生成。
pub struct Origin {
  priv site : &OriginSite
  priv path : KeyPath
}

///|
/// 来源的大类
pub fn Origin::kind(self : Origin) -> SourceKind {
  OriginSite::kind(self.site)
}

///|
/// 展示用的来源描述，例如 `file:config/app.json`、`env:APP_DB_PORT`
pub fn Origin::label(self : Origin) -> String {
  OriginSite::describe(self.site, self.path)
}

///|
/// 能重新读出原始字节时才给
pub fn Origin::locator(self : Origin) -> &Locator? {
  OriginSite::locator(self.site)
}

///|
/// 这个值在配置里的层级路径
pub fn Origin::path(self : Origin) -> KeyPath {
  self.path
}

///|
/// 来源对象本身；需要调用来源自己的方法时用
pub fn Origin::site(self : Origin) -> &OriginSite {
  self.site
}
