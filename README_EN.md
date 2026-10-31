<div align="center">

<img src="https://muvirus.github.io/%E9%A1%B9%E7%9B%AE/moonbit/moonfig/logo/moonfig.png" alt="moonbit logo" width="240">

[中文](README.mbt.md) | **English**

# moonfig

A native configuration library for MoonBit.


**Declare once, gather from many sources.**

</div>

## Contents

- [Goals](#goals)
- [Features](#features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Example](#example)
- [Roadmap](#roadmap)
- [Documentation](#documentation)
- [License](#license)

---

## Goals

moonfig is a comprehensive configuration library built for multi-source configuration: it unifies common config files, environment variables and the command line into one model, merges them according to the configured rules, then reads by key or extracts into a struct. The core is platform-independent and works on every target.

---

## Features

- **Type-safe configuration**: reuses MoonBit's native `derive(FromJson)` mechanism to extract into structs. The library maps config values to Json, translates errors and adds extra checks for easily confused types; no code generator is needed
- **Strict conversions**: reads and extraction check the declared type and reject common cross-type spellings instead of converting implicitly; the only widening is integer→float (`get_float`), and `get_float_strict` turns even that off. Specific types (`BigInt`, a custom `FromJson`, and so on) follow their own rules
- **Many formats**: JSON, INI, `.env`, YAML, TOML, XML, CBOR bytes, or a hand-built `Value` tree can each act as a source
- **Format detection**: `Detector` checks the file suffix first, then the content; when neither decides it raises `UnknownFormat` listing the candidate suffixes
- **Hot reload**: `build_live()` keeps the source list, and `Watcher::poll()` detects file changes and swaps the snapshot; a bad config never takes effect
- **Layered sources**: in-memory defaults, config files, environment variables and command-line flags stack in the order you add them, later ones winning
- **Merge by key**: a later source overrides only the keys it shares with an earlier one; every other key survives
- **Errors that name the culprit**: `MissingKey` / `TypeMismatch` / `ParseError` / `UnknownFormat`, each message carrying the key, the expected type and the actual type
- **Traceable origins**: `origin_of` / `origins()` look a source up by path, and `snapshot()` exports path, value and source together; the display label is generated on demand
- **Validatable**: rule lists by key or a `Validate` impl on your struct, surfacing missing keys, out-of-range values and unknown keys at startup

---

## Installation

moonfig needs the MoonBit toolchain; see the [official installation guide](https://www.moonbitlang.com/download/), and make sure `moon version` works.

Add the module to an existing MoonBit project:

```sh
moon add MuVirus/moonfig
```

Then import the packages you need in `moon.pkg`:

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
`env_source/` and `cli_source/` at the module root; see [Files](#files),
[environment variables](#environment-variables) and
[command line arguments](#command-line-arguments).

To run from a clone:

```sh
git clone https://github.com/MuVirus/moonfig.git
cd moonfig
moon update
moon test
moon run examples/multi_source -- --log-level=debug
```

---

## Quick start

With the dependency installed, stack two sources and the later one wins:

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

Reads match the value's actual type exactly; no implicit conversion is performed, except integer→float widening, which `get_float_strict` turns off. A JSON float extracted into an integer field is a type mismatch, never a truncation:

```moonbit nocheck
using @config {type Config, type StringSource}
using @jsonfmt {type JsonFormat, extract_from}

let cfg = Config::new()
  .add(StringSource::new("{\"db\":{\"port\":\"5432\"}}", JsonFormat::new()))
  .build()

cfg.get_string("db.port")   // "5432"
cfg.get_int("db.port")      // error: key 'db.port': expected Int, got Str

struct TextPort {
  port : String
} derive(FromJson)

struct NumericPort {
  port : Int
} derive(FromJson)

let text : TextPort = extract_from(cfg, "db")       // port = "5432"
let numeric : NumericPort = extract_from(cfg, "db") // error: key 'db.port': expected Int, got Str
```

### Read by key

`MemorySource` holds your defaults; every getter checks the declared type and
never converts, except integer→float widening:

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

cfg.get_string("db.host")        // "localhost"
cfg.get_int("db.port")           // 5432
cfg.get_bool("debug")            // false
cfg.get_float("ratio")           // 0.5
cfg.get_float("db.port")         // 5432.0, integer widened to float
cfg.get_float_strict("db.port")  // error: expected Float, got Int
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

### Files

`FileSource` reads one file; the `Format` you pass decides how to parse it:

```moonbit nocheck
import {
  "MuVirus/moonfig/file_source" @file_source,
}

using @config {type Config}
using @file_source {type FileSource}
using @jsonfmt {type JsonFormat}

let cfg = Config::new()
  .add(FileSource::new("config/app.json", JsonFormat::new()))
  .build()
```

A missing file raises `IoError` (with the path) and a bad payload raises `ParseError`; the `locator` from `origin_of` can read the same file again. Use [`FileSource::auto`](#format-detection) when you do not want to name the format.

### Environment variables

`EnvSource` reads variables with a prefix; the prefix is not part of the keys:

```moonbit nocheck
import {
  "MuVirus/moonfig/env_source" @env_source,
}

using @config {type Config}
using @env_source {type EnvSource}

let cfg = Config::new()
  .add(EnvSource::new("APP_"))  // APP_DB_PORT=6543 → db.port
  .build()
```

Both `_` and `.` split levels, names are lowercased, and values are inferred from their text (`"5432"` → `Int`, `"true"` → `Bool`). `EnvSource::all()` reads every variable. A scalar in the way of a branch, or two variables landing on one path, is an error rather than a guess.

### Command line arguments

`CliSource` reads argv. Pick one value style; do not mix:

```moonbit nocheck
import {
  "MuVirus/moonfig/cli_source" @cli_source,
}

using @config {type Config}
using @cli_source {type CliSource, type CliValueStyle}

let cfg = Config::new()
  .add(
    CliSource::new()
      .with_value_style(CliValueStyle::Separate)  // --start 0
      .with_positional(0, "command")              // simulate
      .with_positional(1, "model")                // model.fmu
      .with_array("tag")                          // --tag a --tag b → ["a", "b"]
      .with_short_option("p", "db.port"),         // -p 5432
  )
  .build()
```

- The default `CliValueStyle::Equals` accepts only `--key=value`; `Separate` accepts only `--key value`. The other form is an error rather than being silently ignored (under `Equals`, `--key value` is just a flag plus a positional argument).
- A bare `--key` is boolean `true` and `--no-key` is `false`. Short options must be registered, and their value form follows the style (`-p=5432` or `-p 5432`); boolean short options can be clustered as `-vq`.
- Paths declared with `.with_array("tag")` collect repeated occurrences into an array; `.with_positional(0, "command")` maps positional 0 to a key.
- Repeated keys that are not declared as arrays mean the later one wins; a scalar and a branch in each other's way is an error.
- Everything after `--` is positional; unmapped positionals and unregistered short options are ignored. Labels never include values, so passwords never reach the logs.

All three sources implement `Source` and stack in `.add` order, later ones winning; see [Stacking sources](#stacking-sources).

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
cfg.snapshot()            // [Entry { ... }], path, value and source together
```

`origin.kind()` is there for pattern matching; `origin.path()` gives a structured `KeyPath`, so you never
have to split a string; `label()` is display-only and generated on demand. Use `origin.locator()` to
re-read the original bytes. The queries merge on demand when `build()` has not run, so they can raise.

Every `snapshot()` entry exposes `path()` / `value()` / `origin()`; tables recurse and arrays stay leaves,
the same rule as `origins()`. An untracked source gives `origin() == None` instead of a made-up label.

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

The code above prints `key 'db.host': expected Int, got Str`; a missing key
prints `missing key 'db.user': no source provides it`.

`extract_from` fails the same way: a missing field raises `MissingKey`, a type
mismatch raises `TypeMismatch`, and the path includes the config path (`db.port`).

---

## Roadmap

| Status | Direction | Items |
|---|---|---|
| ✅ | **Core** | One value type for configuration, merge by key, read by key, read by struct, error handling... |
| ✅ | **Many formats** | Seven formats: JSON, INI, dotenv, YAML, TOML, XML and CBOR |
| ✅ | **External sources** | Configuration files, environment variables, command-line flags, any combination of sources |
| ✅ | **Source tracking** | Which layer a key finally came from |
| ✅ | **Validation** | Required keys, value ranges, custom rules |
| ✅ | **Format detection** | By suffix, by content, an error when neither decides |
| ✅ | **Hot reload** | Poll for file changes, re-read and merge, notify listeners, keep the old config when a new one is bad |
| ⬜ | **Remote configuration** | Fetch configuration files over HTTP/URL, with timeouts, retries and a local fallback. |
| ⬜ | **Encrypted storage** | Parse and securely store encrypted values for sensitive configuration fields. |
| ⬜ | **Preprocessing** | Transform existing configuration text or data without changing the source. |

✅ done (in maintenance)　🚧 in progress　⬜ not started

The full item list and the trade-offs behind them live in
[docs/plan/roadmap.md](docs/plan/roadmap.md).

---

## Documentation

- `moon doc` — generate the API reference into `_build/doc/`
- `moon doc --serve` — start a local preview (http://127.0.0.1:3000 by default)
- [`examples/`](examples/README.md) — five runnable examples, with their commands listed in the index
- `moon coverage analyze -- -f summary` — run the tests and print a coverage summary
- [docs/AGENTS.md](docs/AGENTS.md) — documentation index and writing rules
- [docs/design/cli-args.md](docs/design/cli-args.md) — command line parsing design
- [docs/design/format-detect.md](docs/design/format-detect.md) — format detection design
- [docs/design/hot-reload.md](docs/design/hot-reload.md) — hot reload design

> The documents under `docs/` are written in Chinese.

---

## License

Apache-2.0
