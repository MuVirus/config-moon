[中文](README.mbt.md) | **English**

# moonfig

A native configuration library for MoonBit.

**Declare once, gather from many sources.**

## Contents

- [Features](#features)
- [Quick start](#quick-start)
- [Example](#example)
- [Roadmap](#roadmap)
- [Documentation](#documentation)
- [License](#license)

---

## Features

- **Type-safe configuration**: `derive(FromJson)` generates the deserialization for your config struct, so extracting a value yields that type directly. No code generator, no custom derive trait — MoonBit's own derive mechanism does the work
- **Strict typing**: every read and every extraction checks the declared type; nothing is converted implicitly, and a mismatch is an error
- **Many formats**: JSON, INI, `.env`, YAML, TOML, XML, CBOR bytes, or a hand-built `Value` tree can each act as a source
- **Format detection**: `Detector` checks the file suffix first, then the content; when neither decides it raises `UnknownFormat` listing the candidate suffixes
- **Hot reload**: `build_live()` keeps the source list, and `Watcher::poll()` detects file changes and swaps the snapshot; a bad config never takes effect
- **Layered sources**: in-memory defaults, config files, environment variables and command-line flags stack in the order you add them, later ones winning
- **Merge by key**: a later source overrides only the keys it shares with an earlier one; every other key survives
- **Errors that name the culprit**: `MissingKey` / `TypeMismatch` / `ParseError` / `UnknownFormat`, each message carrying the key, the expected type and the actual type
- **Traceable origins**: `origin_of` / `origins()` give you the source object and a structured key path; the display label is generated on demand
- **Validatable**: rule lists by key or a `Validate` impl on your struct, surfacing missing keys, out-of-range values and unknown keys at startup

---

## Quick start

Add the dependencies to your `moon.pkg`:

```moonbit
import {
  "MuVirus/moonfig/core" @config,
  "MuVirus/moonfig/core/format/json_format" @jsonfmt,
}
```

> **Write the alias out.** MoonBit binds the directory name when the alias is left
> off, so the core package would become `@core`. That compiles, but this project
> spells the alias out everywhere (`@config` / `@jsonfmt`): short, and the user's
> import block survives a future directory reshuffle.

The core package `core/` provides `MemorySource`, `StringSource` and
`BytesSource`: a hand-built `Value` tree, a piece of text, a piece of bytes. Every
other format has a package of its own, named `core/format/<format>_format` and
exposing only `XxxFormat`; add the one you need to your `moon.pkg` and combine it
with `StringSource` / `BytesSource`. The mapping rules live in each package's doc
comment. The file, environment and command-line sources live in `file_source/`,
`env_source/` and `cli_source/` at the module root; see
[below](#files-environment-variables-command-line).

Stack two sources and the later one wins:

```moonbit nocheck
using @config { type Config, type StringSource }
using @jsonfmt { type JsonFormat }

let cfg = Config::new()
  .add(StringSource::new("{\"db\":{\"host\":\"localhost\",\"port\":5432}}", JsonFormat::new()))
  .add(StringSource::new("{\"db\":{\"port\":6543}}", JsonFormat::new()))
  .build()

cfg.get_string("db.host")   // "localhost"   ← from the first source, not overridden
cfg.get_int("db.port")      // 6543          ← overridden by the second
```

---

## Example

### Type safety

Reads match the value's actual type exactly; no implicit conversion is performed. A JSON float extracted into an integer field is a type mismatch, never a truncation:

```moonbit nocheck
using @config {type Config, type StringSource}
using @jsonfmt {type JsonFormat, extract_from}

let cfg = Config::new()
  .add(StringSource::new("{\"db\":{\"port\":\"5432\"}}", JsonFormat::new()))
  .build()

cfg.get_string("db.port")   // "5432"
cfg.get_int("db.port")      // error: 配置项 db.port 类型不符：期望 Int，实际 Str

struct TextPort {
  port : String
} derive(FromJson)

struct NumericPort {
  port : Int
} derive(FromJson)

let text : TextPort = extract_from(cfg, "db")       // port = "5432"
let numeric : NumericPort = extract_from(cfg, "db") // error: expected number, got string
```

### Read by key

`MemorySource` holds your defaults; every getter checks the declared type and
never converts:

```moonbit nocheck
using @config {type Config, type MemorySource, type Value}

let cfg = Config::new()
  .add(
    MemorySource::new(
      Value::table({
        "db": Value::table({ "host": Value::str("localhost"), "port": Value::int(5432L) }),
        "debug": Value::bool(false),
        "ratio": Value::float(0.5),
      }),
    ),
  )
  .build()

cfg.get_string("db.host")   // "localhost"
cfg.get_int("db.port")      // 5432
cfg.get_bool("debug")       // false
cfg.get_float("ratio")      // 0.5
```

### Stacking sources

Sources need not share a format; a later one overrides only the keys it shares:

```moonbit nocheck
using @config {type Config, type StringSource}
using @jsonfmt {type JsonFormat}
using @inifmt {type IniFormat}
using @dotenvfmt {type DotenvFormat}

let cfg = Config::new()
  .add(StringSource::new("{\"db\":{\"host\":\"localhost\",\"port\":5432}}", JsonFormat::new())) // defaults
  .add(StringSource::new("[db]\nport = 6000\n", IniFormat::new()))                              // config file
  .add(StringSource::new("db.port=6543", DotenvFormat::new()))                                  // environment override
  .build()

cfg.get_string("db.host")   // "localhost"   only the first source provides it
cfg.get_int("db.port")      // 6543          the last one wins
```

The default rule is `LastWins`. Use `.with_rule(MergeRule::FirstWins)` to flip the order, `MergeRule::ByKind([...])` to rank by source kind, or pass a custom function.

### Files, environment variables, command line

Each external source is a package of its own, separate from the format packages:

```moonbit nocheck
import {
  "MuVirus/moonfig/file_source" @file_source,
  "MuVirus/moonfig/env_source" @env_source,
  "MuVirus/moonfig/cli_source" @cli_source,
}
```

```moonbit nocheck
using @config {type Config, type MemorySource, type Value}
using @jsonfmt {type JsonFormat}
using @file_source {type FileSource}
using @env_source {type EnvSource}
using @cli_source {type CliSource}

let cfg = Config::new()
  .add(MemorySource::new(Value::table({ "db": Value::table({ "port": Value::int(5432L) }) })))
  .add(FileSource::new("config/app.json", JsonFormat::new()))  // reads the file, format of your choice
  .add(EnvSource::new("APP_"))                                  // APP_DB_PORT=6543 → db.port
  .add(CliSource::new())                                        // --log-level=debug → log.level
  .build()
```

- `FileSource`: a path plus a `Format`. A missing file raises `IoError` (with the path), a bad payload raises `ParseError`; the `locator` from `origin_of` can read the same file again.
- `EnvSource`: reads only variables with the given prefix; both `_` and `.` split levels, names are lowercased, and values are inferred from their text (`"5432"` → `Int`, `"true"` → `Bool`). `EnvSource::all()` reads every variable. A scalar in the way of a branch, or two variables landing on one path, is an error rather than a guess.
- `CliSource`: accepts `--key=value`, `--flag` and `--no-flag`; everything after `--` is positional. The same key twice means the later one wins, but a scalar and a branch in each other's way is an error. The label is the argument name without its value, so passwords never reach the logs.

### Format detection

Hand the path to `FileSource::auto` and leave the format out:

```moonbit nocheck
using @config {type Config}
using @file_source {type FileSource}
using @format_detect {type Detector}
using @jsonfmt {type JsonFormat}
using @tomlfmt {type TomlFormat}
using @yamlfmt {type YamlFormat}

let detector = Detector::new([
  JsonFormat::new(),
  TomlFormat::new(),
  YamlFormat::new(),
])

let cfg = Config::new()
  .add(FileSource::auto("config/app.toml", detector))
  .build()
```

A known suffix selects its format directly. When the suffix is missing or unknown, candidates are asked in order and the first one that looks like a match wins. That order is the priority: put JSON before YAML, since JSON is usually valid YAML too. A known suffix that fails to parse raises `ParseError` instead of silently trying the next candidate; when neither suffix nor content matches, `UnknownFormat` lists the candidate suffixes.

Full example: [examples/format_detect](examples/format_detect/README.md).

### Hot reload

`build_live()` merges like `build()` but keeps the source list for later:

```moonbit nocheck
using @config {type Config, type Rule}
using @file_source {type FileSource}
using @format_detect {type Detector}
using @jsonfmt {type JsonFormat}
using @hot_reload {type Watcher}

let live = Config::new()
  .add(FileSource::auto("config/app.json", Detector::new([JsonFormat::new()])))
  .build_live()

let watcher = @hot_reload.watch(
  live,
  interval=1000,
  on_change=fn(cfg) { println("port = \{cfg.get_int("db.port")}") },
  on_error=fn(error) { println("new config kept out: \{error}") },
)

// Call it from your timer or event loop; true means a change was detected and reload was attempted
watcher.poll()

// Manual reload with validation rules
live.reload(rules=[Rule::int_range("db.port", 1L, 65535L)])
watcher.stop()
```

`watch()` only registers the callbacks and the `LiveConfig`; it does not start a timer. `interval` is a suggestion and the caller owns the cadence, so the library stays independent of any async runtime. `poll()` tracks file sources only and compares bytes rather than mtime; environment variables and command-line arguments have no reliable change event, so use `reload()` for those. A parse or validation failure leaves the old snapshot in place; the next successful `poll()` picks up the fixed file.

Full example: [examples/hot_reload](examples/hot_reload/README.md).

### Source tracking

Every value remembers the layer it came from, so you can ask after reading:

```moonbit nocheck
using @config {type Config, type MemorySource, type Value}

let cfg = Config::new()
  .add(
    MemorySource::new(
      Value::table({ "db": Value::table({ "port": Value::int(5432L) }) }),
    ),
  )
  .build()

let origin = cfg.origin_of("db.port").unwrap()
origin.kind()             // SourceKind::Memory
origin.label()            // "memory"
origin.path().to_string() // "db.port"
cfg.origins()             // [Origin { ... }], leaves only
```

`origin.kind()` is there for pattern matching; `origin.path()` gives a structured `KeyPath`, so you never
have to split a string; `label()` is display-only and generated on demand. Use `origin.locator()` to
re-read the original bytes. The queries merge on demand when `build()` has not run, so they can raise.

### Extract into a struct

Using the compiler's own `derive(FromJson)`:

```moonbit nocheck
using @jsonfmt {extract_from}

struct DbCfg {
  host : String
  port : Int
} derive(FromJson)

let db : DbCfg = extract_from(cfg, "db")
```

Struct fields should not use `Int64` / `UInt64`: core's `FromJson` only accepts JSON strings, which is incompatible with this library's integer mapping. Use `Int64Text` / `UInt64Text` instead and read them with `to_int64()` / `to_uint64()`.

```moonbit nocheck
using @jsonfmt {extract_from, Int64Text}

struct OrderCfg {
  id : Int64Text
} derive(FromJson)

let order : OrderCfg = extract_from(cfg, "order")
order.id.to_int64()   // 9007199254740993, exact even beyond Double's range
```

### Validate

Check the configuration at startup so problems surface early. By key, pass a rule list:

```moonbit nocheck
using @config {type Rule}

cfg.validate([
  Rule::int_range("db.port", 1L, 65535L),
  Rule::one_of("log.level", ["debug", "info", "warn", "error"]),
  Rule::allowed_keys("db", ["host", "port"]),
])
```

After extracting into a struct, put the constraints in its `Validate` impl:

```moonbit nocheck
using @jsonfmt {extract_validated_from}

impl @config.Validate for DbCfg with fn validate(self, prefix) {
  @config.check_int_range(prefix.add("port"), self.port.to_int64(), 1L, 65535L)
}

let db : DbCfg = extract_validated_from(cfg, "db")
```

`validate` stops at the first error, `validate_all` lists them all; missing keys are reported as `MissingKey`, and `allowed_keys` is opt-in for unknown keys. See [validate.md](docs/design/validate.md).

### When it fails

A missing key and a type mismatch raise `MissingKey` / `TypeMismatch`; the
message names the key, the expected type and the actual type:

```moonbit nocheck
try {
  cfg.get_int("db.host")
} catch {
  e => println(e)
}
```

The code above prints `配置项 db.host 类型不符：期望 Int，实际 Str`; a missing
key prints `配置项 db.user 不存在：没有任何来源提供它`.

`extract_from` fails the same way: a missing field raises `MissingKey`, a type
mismatch raises `TypeMismatch`, and the path includes the config path (`db.port`).

---

## Roadmap

| Status | Direction | Items |
|---|---|---|
| 🚧 | **Core** | One value type for configuration, merge by key, read by key, read by struct, error handling... |
| ✅ | **Many formats** | Seven formats: JSON, INI, dotenv, YAML, TOML, XML and CBOR |
| ✅ | **External sources** | Configuration files, environment variables, command-line flags, any combination of sources |
| ✅ | **Source tracking** | Which layer a key finally came from |
| ✅ | **Validation** | Required keys, value ranges, custom rules |
| ✅ | **Format detection** | By suffix, by content, an error when neither decides |
| ✅ | **Hot reload** | Poll for file changes, re-read and merge, notify listeners, keep the old config when a new one is bad |
| ⬜ | **Remote configuration** | Fetch configuration files over HTTP/URL, with timeouts, retries and a local fallback. |
| ⬜ | **Encrypted storage** | Parse and securely store encrypted values for sensitive configuration fields. |

✅ done (in maintenance)　🚧 in progress　⬜ not started

The full item list and the trade-offs behind them live in
[docs/plan/roadmap.md](docs/plan/roadmap.md).

---

## Documentation

- `moon doc` —— generate the API reference into `_build/doc/`
- `moon doc --serve` —— start a local preview (http://127.0.0.1:3000 by default)
- `examples/` —— runnable examples, `moon run examples/<name>`
- [docs/AGENTS.md](docs/AGENTS.md) —— documentation index and writing rules
- [docs/design/format-detect.md](docs/design/format-detect.md) —— format detection design
- [docs/design/hot-reload.md](docs/design/hot-reload.md) —— hot reload design

> The documents under `docs/` are written in Chinese.

---

## License

Apache-2.0
