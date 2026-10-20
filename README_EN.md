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
- **Many formats**: JSON, INI, `.env`, YAML, TOML, XML, or a hand-built `Value` tree can each act as a source
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
mapping rules live in each package's doc comment; the full list of packages is
in [docs/design.md](docs/design.md).

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

Extract a configuration into a struct you declared, using the compiler's own
`derive(FromJson)`. The library generates no code for your types:

```moonbit nocheck
///|
using @jsonsrc {extract_from}

///|
struct DbCfg {
  host : String
  port : Int64
} derive(FromJson)

///|
let db : DbCfg = extract_from(cfg, "db")
```

---

## Roadmap

| Status | Direction | Items |
|---|---|---|
| 🚧 | **Core** | One value type for configuration, merge by key, read by key, read by struct, error handling |
| 🚧 | **Many formats** | CBOR, letting other formats plug in |
| ⬜ | **External sources** | Configuration files, environment variables, any combination of sources |
| ⬜ | **Validation** | Required keys, value ranges, custom rules |
| ⬜ | **Format detection** | By suffix, by content, an error when neither decides |
| ⬜ | **Hot reload** | Watch the file, re-read and merge, notify listeners, keep the old config when a new one is bad |

✅ done (in maintenance)　🚧 in progress　⬜ not started

The full item list and the trade-offs behind them live in
[docs/roadmap.md](docs/roadmap.md).

---

## Documentation

- `moon doc` —— generate the API reference into `_build/doc/`
- `moon doc --serve` —— start a local preview (http://127.0.0.1:3000 by default)
- [docs/roadmap.md](docs/roadmap.md) —— the phased plan and the order of work
- [docs/design.md](docs/design.md) —— type design, merge rules, why the packages are split, worked examples
- [docs/testing.md](docs/testing.md) —— how tests are written here

> The documents under `docs/` are written in Chinese.

---

## License

Apache-2.0
