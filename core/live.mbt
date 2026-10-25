///|
/// 可热更新的配置：保留来源清单，每次重读都重新 `collect` + 合并。
///
/// `build()` 把来源摊平成一棵树，之后文件再改也不会变；`build_live()` 在拿到
/// 第一份快照的同时留下来源清单，之后 `reload()` / `poll()` 可以从头再读一遍。
///
/// 读者拿到的 `current()` 永远是一棵完整的树。重读失败时旧快照不动，所以
/// 业务代码不会看到合并到一半的状态。
pub struct LiveConfig {
  priv sources : Array[&Source]
  priv rule : MergeRule
  priv mut current : Config
  priv locators : Array[&Locator]
  priv mut snapshots : Array[Bytes]
}

///|
/// 按当前来源和合并规则重新算出一棵树。
fn LiveConfig::rebuild(self : LiveConfig) -> Config raise ConfigError {
  let draft = Config::{
    sources: self.sources.copy(),
    rule: self.rule,
    value: Value::table(Map([], capacity=0)),
  }
  draft.build()
}

///|
/// 所有文件类来源里能反推字节的那些，保持来源添加顺序。
///
/// 用来源自己的 `raw_locator()`，而不是从合并结果反查：被后面的来源覆盖掉的
/// 文件也要能触发重读，否则改了底层文件不会生效。
fn file_locators(sources : Array[&Source]) -> Array[&Locator] {
  let locators : Array[&Locator] = []
  for source in sources {
    if source.kind() == SourceKind::File {
      match source.raw_locator() {
        Some(locator) => locators.push(locator)
        None => ()
      }
    }
  }
  locators
}

///|
/// 读一轮文件字节，作为下一次 `poll` 的比较基准。
fn read_snapshots(locators : Array[&Locator]) -> Array[Bytes] raise ConfigError {
  locators.map((locator) => locator.read())
}

///|
/// 和 `build()` 一样先合并一次，但保留来源清单，供之后重读。
///
/// Example:
///
/// ```mbt check
/// test {
///   let live = @config.Config::new()
///     .add(
///       @config.MemorySource::new(
///         @config.Value::table({ "debug": @config.Value::bool(false) }),
///       ),
///     )
///     .build_live()
///   assert_false(live.current().get_bool("debug"))
/// }
/// ```
pub fn Config::build_live(self : Config) -> LiveConfig raise ConfigError {
  let sources = self.sources.copy()
  let rule = self.rule
  let locators = file_locators(sources)
  // 先记基准再 build：如果文件在 build 期间改了，下一次 poll 会看到差异，
  // 不会出现「快照已经是新内容、current 还是旧内容」的窗口。
  let snapshots = read_snapshots(locators)
  let current = self.build()
  { sources, rule, current, locators, snapshots, }
}

///|
/// 当前快照。业务代码每次要用最新值时重新拿一次。
pub fn LiveConfig::current(self : LiveConfig) -> Config {
  self.current
}

///|
/// 手动重读：重新 collect 所有来源，按原来的规则合并，必要时再校验。
///
/// 读文件、解析、合并、校验任何一步失败都会抛错，`current` 保持旧快照。
pub fn LiveConfig::reload(
  self : LiveConfig,
  rules~ : Array[Rule] = [],
) -> Unit raise ConfigError {
  let snapshots = read_snapshots(self.locators)
  let next = self.rebuild()
  if !rules.is_empty() {
    next.validate(rules)
  }
  self.current = next
  self.snapshots = snapshots
}

///|
/// 检查文件类来源有没有变化；有变化才重读一次。
///
/// 返回 `true` 表示检测到变化并尝试了 `reload()`；失败会抛错，旧快照保留，
/// 下一次 `poll()` 还会继续尝试。返回 `false` 表示文件内容没变。
///
/// 只比较文件内容，不看 mtime：配置很小，直接比字节最稳。
pub fn LiveConfig::poll(
  self : LiveConfig,
  rules~ : Array[Rule] = [],
) -> Bool raise ConfigError {
  let mut changed = false
  for i, locator in self.locators {
    if locator.read() != self.snapshots[i] {
      changed = true
      break
    }
  }
  if changed {
    self.reload(rules~)
  }
  changed
}
