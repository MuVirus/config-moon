///|
/// moonfig 示例：自动发现格式。
///
/// 运行：`moon run examples/format_detect`
///
/// `.toml` / `.yaml` 后缀直接决定解析器；`feature.conf` 的后缀不认识，
/// 按内容认出 JSON；`notes.txt` 两者都不像，报 `UnknownFormat`。

///|
using @config {type Config, type ConfigError}

///|
using @file_source {type FileSource}

///|
using @detect {type Detector}

///|
using @jsonfmt {type JsonFormat}

///|
using @tomlfmt {type TomlFormat}

///|
using @yamlfmt {type YamlFormat}

///|
/// 候选顺序就是内容判断的优先级：JSON 特征最强，放最前面。
fn detector() -> Detector raise ConfigError {
  Detector::new([JsonFormat::new(), TomlFormat::new(), YamlFormat::new()])
}

///|
/// 路径交给 `FileSource::auto`，格式由检测器决定。
fn load(path : String) -> Config raise ConfigError {
  Config::new().add(FileSource::auto(path, detector())).build()
}

///|
fn show(path : String) -> Unit raise ConfigError {
  let cfg = load(path)
  println("\{path} -> db.port = \{cfg.get_int("db.port")}")
}

///|
fn main raise {
  show("examples/format_detect/config/app.toml")
  show("examples/format_detect/config/legacy.yaml")
  show("examples/format_detect/config/feature.conf")
  show("examples/format_detect/config/notes.txt") catch {
    error => println("expected failure: \{error}")
  }
}
