///|
/// 热更新 watcher 的句柄。
///
/// `watch` 只登记参数并返回句柄，由调用方按自己的节奏调用 `poll()`：
/// 定时器在哪一層由调用方决定，`LiveConfig` 和回调逻辑不绑死某个运行时。
/// `stop()` 之后 `poll()` 不再做任何事。
pub struct Watcher {
  priv live : @config.LiveConfig
  priv interval : Int32
  priv on_change : (@config.Config) -> Unit raise @config.ConfigError
  priv on_error : (@config.ConfigError) -> Unit raise @config.ConfigError
  priv stopped : @ref.Ref[Bool]
}

///|
/// 登记一个 watcher。
///
/// - 启动时不回调；内容没变不回调；两次保存落在同一轮里只 reload 一次。
/// - 先替换快照，再回调，所以回调里 `live.current()` 已经是新值。
/// - 解析、IO、校验失败交给 `on_error`，旧快照继续用。
/// - 回调自己抛错也只上报，不会把新快照退回去。
/// - `stop()` 之后不再回调。
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
///   let watcher = @hot_reload.watch(live)
///   assert_false(watcher.poll())
///   watcher.stop()
///   assert_true(watcher.is_stopped())
/// }
/// ```
pub fn watch(
  live : @config.LiveConfig,
  interval~ : Int32 = 1000,
  on_change~ : (@config.Config) -> Unit raise @config.ConfigError = fn(_) {  },
  on_error~ : (@config.ConfigError) -> Unit raise @config.ConfigError = fn(_) {

  },
) -> Watcher {
  { live, interval, on_change, on_error, stopped: @ref.Ref(false), }
}

///|
/// 停止轮询
pub fn Watcher::stop(self : Watcher) -> Unit {
  self.stopped.val = true
}

///|
/// 是否已经停止
pub fn Watcher::is_stopped(self : Watcher) -> Bool {
  self.stopped.val
}

///|
/// 建议的轮询间隔（毫秒）；实际调度由调用方决定
pub fn Watcher::interval(self : Watcher) -> Int32 {
  self.interval
}

///|
/// 把错误交给 `on_error`；回调自己抛错也只吞掉，不改变快照。
fn Watcher::report(self : Watcher, error : @config.ConfigError) -> Unit {
  let callback = self.on_error
  callback(error) catch {
    _ => ()
  }
}

///|
/// 跑一轮：`LiveConfig::poll` 检测到变化时先替换快照，再回调。
///
/// 返回 `true` 表示这一轮检测到变化并尝试了 reload；失败交给 `on_error`。
/// 返回 `false` 表示没变化、已经停止，或 reload 失败。
pub fn Watcher::poll(self : Watcher) -> Bool {
  if self.stopped.val {
    return false
  }
  let changed = self.live.poll() catch {
    error => {
      self.report(error)
      false
    }
  }
  if changed {
    let callback = self.on_change
    callback(self.live.current()) catch {
      error => self.report(error)
    }
  }
  changed
}
