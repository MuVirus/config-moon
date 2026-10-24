///|
/// moonfig 示例：整数与字符串不会互相顶替。
///
/// 运行：`moon run examples/strict_types`
///
/// 两条来源内容完全一样，只有 `port` 的写法不同——一个是数字 `5432`，
/// 一个是字符串 `"5432"`。下面逐个展示它在两层 API 上的结果：
///
/// - 按键取值：直接看 `Value` 的形状，形状不符就报错，不做转换
/// - 提取到结构体：整数映射为 JSON 数字、字符串映射为 JSON 字符串，
///   两条路互不交叉

///|
using @config {type Config, type StringSource}

///|
using @jsonfmt {type JsonFormat, extract_from}

///|
/// 端口声明成数字，只该接受数字来源
struct NumericPort {
  port : Int32
  name : String
} derive(@json.FromJson)

///|
pub extend NumericPort with @json.FromJson::{from_json}

///|
/// 端口声明成字符串，只该接受字符串来源
struct TextualPort {
  port : String
  name : String
} derive(@json.FromJson)

///|
pub extend TextualPort with @json.FromJson::{from_json}

///|
/// 取整数；失败时把错误原文带回来，方便直接看提示
fn read_int(cfg : Config, path : String) -> String {
  cfg.get_int(path).to_string() catch {
    e => "报错：\{e}"
  }
}

///|
/// 取字符串；失败时把错误原文带回来
fn read_str(cfg : Config, path : String) -> String {
  cfg.get_string(path) catch {
    e => "报错：\{e}"
  }
}

///|
/// 数字端口结构体
fn read_numeric(cfg : Config) -> String {
  try {
    let v : NumericPort = extract_from(cfg, "db")
    "port = \{v.port}，name = \{v.name}"
  } catch {
    e => "报错：\{e}"
  }
}

///|
/// 字符串端口结构体
fn read_textual(cfg : Config) -> String {
  try {
    let v : TextualPort = extract_from(cfg, "db")
    "port = \"\{v.port}\"，name = \{v.name}"
  } catch {
    e => "报错：\{e}"
  }
}

///|
fn main raise {
  let numeric = Config::new()
    .add(
      StringSource::new(
        "{\"db\":{\"port\":5432,\"name\":\"main\"}}",
        JsonFormat::new(),
      ),
    )
    .build()
  let textual = Config::new()
    .add(
      StringSource::new(
        "{\"db\":{\"port\":\"5432\",\"name\":\"main\"}}",
        JsonFormat::new(),
      ),
    )
    .build()

  let n_int = read_int(numeric, "db.port")
  let t_int = read_int(textual, "db.port")
  let n_str = read_str(numeric, "db.port")
  let t_str = read_str(textual, "db.port")

  println("== 按键取值 ==")
  println("数字来源   get_int    -> \{n_int}") // 5432
  println("字符串来源 get_int    -> \{t_int}") // 报错：期望 Int，实际 Str
  println("数字来源   get_string -> \{n_str}") // 报错：期望 Str，实际 Int
  println("字符串来源 get_string -> \{t_str}") // "5432"

  let n_num = read_numeric(numeric)
  let t_num = read_numeric(textual)
  let n_txt = read_textual(numeric)
  let t_txt = read_textual(textual)

  println("")
  println("== 提取到结构体 ==")
  println("数字来源   -> NumericPort  \{n_num}") // port = 5432，name = main
  println("数字来源   -> TextualPort  \{n_txt}") // 报错：配置项 db.port 类型不符：期望 Str，实际 Int
  println("字符串来源 -> NumericPort  \{t_num}") // 报错：配置项 db.port 类型不符：期望 Int，实际 Str
  println("字符串来源 -> TextualPort  \{t_txt}") // port = "5432"，name = main
}
