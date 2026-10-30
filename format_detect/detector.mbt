///|
/// 自动发现格式：先看文件后缀，后缀不认识再看内容。
///
/// `Detector` 自己就是一种 `Format`，所以 `StringSource` / `BytesSource`
/// 可以直接把它当格式传进去；只有文件需要路径，才用 `FileSource::auto`。
///
/// 候选顺序就是优先级：内容判断时从前往后问，第一个说「像」的胜出。
/// 同一个后缀被两个候选认领时，构造阶段直接报错。
pub struct Detector {
  priv formats : Array[&@config.Format]
  priv by_suffix : Map[String, &@config.Format]
  priv suffixes : Array[String]
}

///|
/// 后缀统一成小写、不带前导点，`JSON` 和 `.json` 算同一个。
fn normalize_suffix(suffix : String) -> String {
  suffix.trim().trim_start(chars=".").to_lower().to_owned()
}

///|
/// 取文件名的最后一段后缀；没有点、或点后面是空串时返回 `None`。
fn file_suffix(path : String) -> String? {
  let parts = path.split("/").collect()
  let name = parts[parts.length() - 1]
  let pieces = name.split("\\").collect()
  let base = pieces[pieces.length() - 1]
  match base.rev_find(".") {
    Some(dot) => {
      let suffix = base.view(start_offset=dot + 1).to_lower().to_owned()
      if suffix.is_empty() {
        None
      } else {
        Some(suffix)
      }
    }
    None => None
  }
}

///|
/// 从候选格式构造检测器。
///
/// 后缀重复会抛 `ParseError`，不让候选顺序决定谁赢。
///
/// Example:
///
/// ```mbt check
/// test {
///   let detector = @format_detect.Detector::new([@json_format.JsonFormat::new()])
///   let cfg = @config.Config::new()
///     .add(@config.StringSource::new("{\"db\": {\"port\": 5432}}", detector))
///     .build()
///   assert_eq(cfg.get_int("db.port"), 5432L)
/// }
/// ```
pub fn Detector::new(
  formats : Array[&@config.Format],
) -> Detector raise @config.ConfigError {
  let by_suffix : Map[String, &@config.Format] = Map(
    [],
    capacity=formats.length(),
  )
  let suffixes : Array[String] = []
  for format in formats {
    for suffix in format.suffixes() {
      let key = normalize_suffix(suffix)
      if !key.is_empty() {
        if by_suffix.contains(key) {
          raise @config.ConfigError::ParseError(
            "duplicate suffix .\{key} declared by format candidates",
          )
        }
        by_suffix[key] = format
        suffixes.push(key)
      }
    }
  }
  { formats, by_suffix, suffixes, }
}

///|
/// 这个检测器认哪些后缀，不含前导点
pub fn Detector::supported_suffixes(self : Detector) -> Array[String] {
  self.suffixes.copy()
}

///|
/// 后缀认识就用对应格式；不认识或没有后缀时才按内容猜。
///
/// 选中的格式解析失败会原样抛 `ParseError`，不会偷偷换下一个候选。
pub impl @config.Format for Detector with fn decode_path(
  self : Detector,
  path : String,
  bytes : Bytes,
) -> @config.Value raise @config.ConfigError {
  match file_suffix(path) {
    Some(suffix) =>
      match self.by_suffix.get(suffix) {
        Some(format) => return format.decode(bytes)
        None => ()
      }
    None => ()
  }
  self.decode_content(path, bytes)
}

///|
/// 只看内容：按候选顺序做 `sniff`，第一个认为「像」的胜出。
fn Detector::decode_content(
  self : Detector,
  name : String,
  bytes : Bytes,
) -> @config.Value raise @config.ConfigError {
  for format in self.formats {
    if format.sniff(bytes) {
      return format.decode(bytes)
    }
  }
  raise @config.ConfigError::UnknownFormat(name, self.suffixes.copy())
}

///|
/// 没有路径时只能看内容；文件用 `decode_path` 才会先看后缀。
pub impl @config.Format for Detector with fn decode(
  self : Detector,
  bytes : Bytes,
) -> @config.Value raise @config.ConfigError {
  self.decode_content("content", bytes)
}

///|
pub impl @config.Format for Detector with fn suffixes(self : Detector) -> Array[
  String,
] {
  self.suffixes.copy()
}

///|
pub impl @config.Format for Detector with fn sniff(
  self : Detector,
  bytes : Bytes,
) -> Bool {
  for format in self.formats {
    if format.sniff(bytes) {
      return true
    }
  }
  false
}

///|
pub extend Detector with @config.Format::{decode, decode_path, suffixes, sniff}
