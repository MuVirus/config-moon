// Blackbox tests for the hot-reload watcher.

///|
using @config {type Config, type ConfigError}

///|
fn test_path() -> String {
  "tmp_moonfig_hot_reload.json"
}

///|
fn remove_test_file() -> Unit {
  let path = test_path()
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
fn detector() -> @format_detect.Detector raise ConfigError {
  @format_detect.Detector::new([@json_format.JsonFormat::new()])
}

///|
fn live_config() -> @config.LiveConfig raise ConfigError {
  Config::new()
  .add(@file_source.FileSource::auto(test_path(), detector()))
  .build_live()
}

///|
fn record_port(cfg : Config, changes : Array[Int64]) -> Unit {
  changes.push(cfg.get_int("db.port") catch { _ => -1L })
}

///|
fn raise_from_callback(_ : Config) -> Unit raise ConfigError {
  raise ConfigError::ParseError("callback failed")
}

///|
test "watcher reloads changed files and reports errors" {
  remove_test_file()
  @fs.write_string_to_file(test_path(), "{\"db\": {\"port\": 5432}}")
  let live = live_config()
  let changes : Array[Int64] = []
  let errors : Array[String] = []
  let watcher = @hot_reload.watch(
    live,
    interval=10,
    on_change=fn(cfg) { record_port(cfg, changes) },
    on_error=fn(error) { errors.push(error.to_string()) },
  )
  assert_eq(watcher.interval(), 10)
  assert_false(watcher.poll())
  assert_true(changes.is_empty())
  @fs.write_string_to_file(test_path(), "{\"db\": {\"port\": 5433}}")
  assert_true(watcher.poll())
  assert_eq(changes, [5433L])
  // bad config：回调 on_error，旧快照不动
  @fs.write_string_to_file(test_path(), "not json")
  assert_false(watcher.poll())
  assert_eq(errors.length(), 1)
  assert_eq(live.current().get_int("db.port"), 5433L)
  // 修好以后继续更新
  @fs.write_string_to_file(test_path(), "{\"db\": {\"port\": 5434}}")
  assert_true(watcher.poll())
  assert_eq(changes, [5433L, 5434L])
  // 停止后不再轮询
  watcher.stop()
  assert_true(watcher.is_stopped())
  @fs.write_string_to_file(test_path(), "{\"db\": {\"port\": 5435}}")
  assert_false(watcher.poll())
  assert_eq(changes, [5433L, 5434L])
  remove_test_file()
}

///|
test "a callback error does not roll back the new snapshot" {
  remove_test_file()
  @fs.write_string_to_file(test_path(), "{\"db\": {\"port\": 5432}}")
  let live = live_config()
  let errors : Array[String] = []
  let watcher = @hot_reload.watch(live, on_change=raise_from_callback, on_error=fn(
    error,
  ) {
    errors.push(error.to_string())
  })
  @fs.write_string_to_file(test_path(), "{\"db\": {\"port\": 5433}}")
  assert_true(watcher.poll())
  assert_eq(errors.length(), 1)
  assert_eq(live.current().get_int("db.port"), 5433L)
  remove_test_file()
}
