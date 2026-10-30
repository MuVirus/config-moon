// Blackbox tests for hot-reload snapshots.

///|
/// 测试用来源：内容放在一个共享array里，`poll` 能看到变化
struct MutableSource {
  bytes : Array[String]
}

///|
fn MutableSource::new(bytes : Array[String]) -> MutableSource {
  { bytes, }
}

///|
impl @config.Locator for MutableSource with fn read(self : MutableSource) -> Bytes raise @config.ConfigError {
  @utf8.encode(self.bytes[0])
}

///|
impl @config.OriginSite for MutableSource with fn kind(_ : MutableSource) -> @config.SourceKind {
  @config.SourceKind::File
}

///|
impl @config.OriginSite for MutableSource with fn describe(
  _ : MutableSource,
  _ : @config.KeyPath,
) -> String {
  "file:mutable"
}

///|
impl @config.OriginSite for MutableSource with fn locator(self : MutableSource) -> &@config.Locator? {
  Some(self as &@config.Locator)
}

///|
impl @config.Source for MutableSource with fn kind(_ : MutableSource) -> @config.SourceKind {
  @config.SourceKind::File
}

///|
impl @config.Source for MutableSource with fn raw_locator(self : MutableSource) -> &@config.Locator? {
  Some(self as &@config.Locator)
}

///|
impl @config.Source for MutableSource with fn collect(self : MutableSource) -> @config.Layer raise @config.ConfigError {
  let text = self.bytes[0]
  if text == "bad" {
    raise @config.ConfigError::ParseError("bad config")
  }
  @config.Layer::new(
    @config.Value::table({ "text": @config.Value::str(text) }),
    Some(self as &@config.OriginSite),
  )
}

///|
test "build_live keeps a snapshot and reload replaces it" {
  let state = ["one"]
  let live = @config.Config::new().add(MutableSource::new(state)).build_live()
  assert_eq(live.current().get_string("text"), "one")
  state[0] = "two"
  // current() 不会自己变，轮询才发现
  assert_eq(live.current().get_string("text"), "one")
  assert_true(live.poll())
  assert_eq(live.current().get_string("text"), "two")
  // 内容没变就不 reload
  assert_false(live.poll())
}

///|
test "a failed reload keeps the old snapshot" {
  let state = ["one"]
  let live = @config.Config::new().add(MutableSource::new(state)).build_live()
  state[0] = "bad"
  let error = try {
    ignore(live.poll())
    None
  } catch {
    e => Some(e)
  }
  assert_true(error is Some(@config.ConfigError::ParseError(_)))
  assert_eq(live.current().get_string("text"), "one")
  // 修好以后再轮询一次，新值才进来
  state[0] = "two"
  assert_true(live.poll())
  assert_eq(live.current().get_string("text"), "two")
}

///|
test "poll tracks file sources even when their keys are overridden" {
  let base = MutableSource::new(["base"])
  let top = MutableSource::new(["top"])
  let live = @config.Config::new().add(base).add(top).build_live()
  assert_eq(live.current().get_string("text"), "top")
  base.bytes[0] = "base-changed"
  // base 的键被 top 覆盖了，来源树里看不到 base，但它仍然是文件来源
  assert_true(live.poll())
  assert_eq(live.current().get_string("text"), "top")
}

///|
test "reload applies validation before replacing the snapshot" {
  let live = @config.Config::new()
    .add(
      @config.MemorySource::new(
        @config.Value::table({ "port": @config.Value::int(70000L) }),
      ),
    )
    .build_live()
  let error = try {
    live.reload(rules=[@config.Rule::int_range("port", 1L, 65535L)])
    None
  } catch {
    e => Some(e)
  }
  assert_true(error is Some(@config.ConfigError::InvalidValue(_, _, _)))
  assert_eq(live.current().get_int("port"), 70000L)
}
