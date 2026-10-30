///|
/// moonfig 示例：配置文件热更新。
///
/// 运行：`moon run examples/hot_reload`
///
/// 示例手动调用 `Watcher::poll()`；真实程序用自己的定时器或事件循环调用同一个方法。
/// `watch()` 只登记 `LiveConfig` 和回调，不启动定时器。

///|
using @config {type Config}

///|
using @file_source {type FileSource}

///|
using @format_detect {type Detector}

///|
using @jsonfmt {type JsonFormat}

///|
fn demo_path() -> String {
  "_build/hot_reload_example.json"
}

///|
fn detector() -> Detector raise {
  Detector::new([JsonFormat::new()])
}

///|
fn write_port(port : Int32) -> Unit raise {
  @fs.write_string_to_file(demo_path(), "{\"db\": {\"port\": \{port}}}")
}

///|
fn show(label : String, cfg : Config) -> Unit {
  let port = cfg.get_int("db.port") catch { _ => -1L }
  println("\{label}: db.port = \{port}")
}

///|
fn main raise {
  write_port(5432)
  let live = Config::new()
    .add(FileSource::auto(demo_path(), detector()))
    .build_live()
  let watcher = @reload.watch(
    live,
    interval=1000,
    on_change=fn(cfg) { show("on_change", cfg) },
    on_error=fn(error) { println("on_error: \{error}") },
  )

  show("initial", live.current())
  println("no file change, poll() = \{watcher.poll()}")

  write_port(6543)
  println("file changed, poll() = \{watcher.poll()}")
  show("current", live.current())

  @fs.write_string_to_file(demo_path(), "not json")
  println("bad config written, poll() = \{watcher.poll()}")
  show("still the old value", live.current())

  write_port(7000)
  println("fixed, poll() = \{watcher.poll()}")
  show("current", live.current())

  watcher.stop()
  println("stopped = \{watcher.is_stopped()}")
  @fs.remove_file(demo_path()) catch {
    _ => ()
  }
}
