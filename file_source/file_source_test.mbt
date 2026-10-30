// Blackbox tests for the file source.

///|
using @config {type Config, type ConfigError, type SourceKind}

///|
using @file_source {type FileSource}

///|
/// 测试用格式：把文件内容放进 `text` 键
struct TextFormat {}

///|
impl @config.Format for TextFormat with fn decode(_ : TextFormat, bytes : Bytes) -> @config.Value raise @config.ConfigError {
  let text = @utf8.decode(bytes) catch {
    _ => raise @config.ConfigError::ParseError("file is not valid UTF-8")
  }
  @config.Value::table({ "text": @config.Value::str(text) })
}

///|
fn test_path() -> String {
  "tmp_moonfig_file_source_test.txt"
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
/// 文件内容交给格式，读出来能直接按键取值
test "FileSource reads a file and decodes it" {
  let path = test_path()
  remove_test_file()
  @fs.write_string_to_file(path, "hello")
  let cfg = Config::new().add(FileSource::new(path, TextFormat::{ })).build()
  assert_eq(cfg.get_string("text"), "hello")
  remove_test_file()
}

///|
/// 来源报 `File`，标签带路径，`locator` 能重新读出同一份字节
test "FileSource reports a file origin with a locator" {
  let path = test_path()
  remove_test_file()
  @fs.write_string_to_file(path, "hello")
  let cfg = Config::new().add(FileSource::new(path, TextFormat::{ })).build()
  let origin = cfg.origin_of("text").unwrap()
  assert_eq(origin.kind(), SourceKind::File)
  assert_eq(origin.label(), "file:\{path}")
  match origin.locator() {
    Some(locator) => {
      let bytes = @config.Locator::read(locator) catch { _ => b"" }
      let text = @utf8.decode(bytes) catch { _ => "" }
      assert_eq(text, "hello")
    }
    None => assert_true(false)
  }
  remove_test_file()
}

///|
/// 文件不存在时是 `IoError`，消息里带路径，不是 `ParseError`
test "FileSource reports IoError when the file is missing" {
  let path = "tmp_moonfig_missing_file.txt"
  remove_test_file()
  let message = try {
    let source = FileSource::new(path, TextFormat::{ })
    ignore(@config.Source::collect(source))
    "no error"
  } catch {
    ConfigError::IoError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains(path))
}

///|
fn remove_file(path : String) -> Unit {
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
fn auto_detector() -> @format_detect.Detector raise @config.ConfigError {
  @format_detect.Detector::new([@json_format.JsonFormat::new()])
}

///|
/// `auto` 对有后缀的文件直接走后缀
test "FileSource::auto uses the file suffix" {
  let path = "tmp_moonfig_auto_suffix.json"
  remove_file(path)
  @fs.write_string_to_file(path, "{\"db\": {\"port\": 5432}}")
  let cfg = Config::new().add(FileSource::auto(path, auto_detector())).build()
  assert_eq(cfg.get_int("db.port"), 5432L)
  remove_file(path)
}

///|
/// 没有后缀时 `auto` 按内容猜
test "FileSource::auto sniffs a file without a suffix" {
  let path = "tmp_moonfig_auto_no_suffix"
  remove_file(path)
  @fs.write_string_to_file(path, "{\"db\": {\"port\": 5432}}")
  let cfg = Config::new().add(FileSource::auto(path, auto_detector())).build()
  assert_eq(cfg.get_int("db.port"), 5432L)
  remove_file(path)
}

///|
/// 后缀认识但内容写坏：不换解析器，直接报解析错误
test "FileSource::auto does not fall back after a known suffix fails" {
  let path = "tmp_moonfig_auto_bad.json"
  remove_file(path)
  @fs.write_string_to_file(path, "not json")
  let error = try {
    ignore(Config::new().add(FileSource::auto(path, auto_detector())).build())
    None
  } catch {
    e => Some(e)
  }
  assert_true(error is Some(ConfigError::ParseError(_)))
  remove_file(path)
}
