// Blackbox tests for exporting a config snapshot with origins.

///|
test "snapshot exports path, value and origin for every leaf" {
  let cfg = @config.Config::new()
    .add(
      MemorySource::new(
        Value::table({
          "db": Value::table({
            "host": Value::str("localhost"),
            "port": Value::int(5432L),
          }),
          "hosts": Value::array([Value::str("a"), Value::str("b")]),
        }),
      ),
    )
    .build()
  let entries = cfg.snapshot()
  assert_eq(entries.length(), 3)
  let labels = entries.map(fn(entry) {
    "\{entry.path().to_string()}=\{entry.origin().unwrap().label()}"
  })
  assert_true(labels.contains("db.host=memory"))
  assert_true(labels.contains("db.port=memory"))
  assert_true(labels.contains("hosts=memory"))
  let mut hosts : @config.Entry? = None
  for entry in entries {
    if entry.path().to_string() == "hosts" {
      hosts = Some(entry)
    }
  }
  let hosts = hosts.unwrap()
  assert_true(
    hosts.value().kind is ValueKind::Array(items) && items.length() == 2,
  )
  assert_eq(hosts.origin().unwrap().kind(), SourceKind::Memory)
}

///|
test "snapshot keeps untracked leaves without an origin" {
  let cfg = @config.Config::new()
    .add(QuietSource::{ value: Value::table({ "a": Value::int(1L) }), })
    .build()
  let entries = cfg.snapshot()
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].path().to_string(), "a")
  assert_true(entries[0].origin() is None)
  assert_true(entries[0].value().kind is ValueKind::Int(1L))
  assert_eq(cfg.origins().length(), 0)
}
