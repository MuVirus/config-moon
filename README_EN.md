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
- **Merge by key**: a later source overrides only the keys it shares with an earlier one; every other key survives
- **Errors that name the culprit**: `MissingKey` / `TypeMismatch` / `ParseError`, each message carrying the key, the expected type and the actual type

---

## Quick start

Add the dependencies to your `moon.pkg`:

```moonbit
import {
  "MuVirus/moonfig/core" @config,
  "MuVirus/moonfig/core/source/json_source" @jsonsrc,
}
```

> **Write the alias out.** MoonBit binds the directory name when the alias is left
> off, so the core package would become `@core`. That compiles, but this project
> spells the alias out everywhere (`@config` / `@jsonsrc`): short, and the user's
> import block survives a future directory reshuffle.

The core package `core/` provides `MemorySource` (holds a hand-built `Value`
tree). Every other format has a package of its own, named
`core/source/<format>_source` — add the one you need to your `moon.pkg`. The
mapping rules live in each package's doc comment.

Stack two sources and the later one wins:

```moonbit nocheck
using @config { type Config }
using @jsonsrc { type JsonSource }

let cfg = Config::new()
  .add(JsonSource::from_str("{\"db\":{\"host\":\"localhost\",\"port\":5432}}"))
  .add(JsonSource::from_str("{\"db\":{\"port\":6543}}"))
  .build()

cfg.get_string("db.host")   // "localhost"   ← from the first source, not overridden
cfg.get_int("db.port")      // 6543          ← overridden by the second
```

---

## Example

### Type safety

Reads match the value's actual type exactly; no implicit conversion is performed:

```moonbit nocheck
using @config {type Config}
using @jsonsrc {type JsonSource, extract_from}

let cfg = Config::new()
  .add(JsonSource::from_str("{\"db\":{\"port\":\"5432\"}}"))
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
using @config {type Config}
using @jsonsrc {type JsonSource}
using @inisrc {type IniSource}
using @dotenvsrc {type DotenvSource}

let cfg = Config::new()
  .add(JsonSource::from_str("{\"db\":{\"host\":\"localhost\",\"port\":5432}}")) // defaults
  .add(IniSource::from_str("[db]\nport = 6000\n"))                              // config file
  .add(DotenvSource::from_str("db.port=6543"))                                  // environment override
  .build()

cfg.get_string("db.host")   // "localhost"   only the first source provides it
cfg.get_int("db.port")      // 6543          the last one wins
```

### Extract into a struct

Using the compiler's own `derive(FromJson)`:

```moonbit nocheck
using @jsonsrc {extract_from}

struct DbCfg {
  host : String
  port : Int
} derive(FromJson)

let db : DbCfg = extract_from(cfg, "db")
```

Struct fields should not use `Int64` / `UInt64`: core's `FromJson` only accepts JSON strings, which is incompatible with this library's integer mapping. Use `Int64Text` / `UInt64Text` instead and read them with `to_int64()` / `to_uint64()`.

```moonbit nocheck
using @jsonsrc {extract_from, Int64Text}

struct OrderCfg {
  id : Int64Text
} derive(FromJson)

let order : OrderCfg = extract_from(cfg, "order")
order.id.to_int64()   // 9007199254740993, exact even beyond Double's range
```

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
| 🚧 | **Core** | One value type for configuration, merge by key, read by key, read by struct, error handling |
| 🚧 | **Many formats** | letting other formats plug in |
| ⬜ | **External sources** | Configuration files, environment variables, any combination of sources |
| ⬜ | **Validation** | Required keys, value ranges, custom rules |
| ⬜ | **Format detection** | By suffix, by content, an error when neither decides |
| ⬜ | **Hot reload** | Watch the file, re-read and merge, notify listeners, keep the old config when a new one is bad |

✅ done (in maintenance)　🚧 in progress　⬜ not started

The full item list and the trade-offs behind them live in
[docs/plan/roadmap.md](docs/plan/roadmap.md).

---

## Documentation

- `moon doc` —— generate the API reference into `_build/doc/`
- `moon doc --serve` —— start a local preview (http://127.0.0.1:3000 by default)
- `examples/` —— runnable examples, `moon run examples/<name>`
- [docs/AGENTS.md](docs/AGENTS.md) —— documentation index and writing rules

> The documents under `docs/` are written in Chinese.

---

## License

Apache-2.0
