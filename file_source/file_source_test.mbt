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
    _ => raise @config.ConfigError::ParseError("文件不是合法的 UTF-8")
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
  assert_eq(origin.kind, SourceKind::File)
  assert_eq(origin.label, "file:\{path}")
  match origin.locator {
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
    "没有报错"
  } catch {
    ConfigError::IoError(message) => message
    e => e.to_string()
  }
  assert_true(message.contains(path))
}
