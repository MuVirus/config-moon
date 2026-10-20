# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## What this project is

`moonfig` is a configuration library for MoonBit. It reads configuration
from multiple sources (JSON text, in-memory tables, and later more formats),
normalizes everything into one intermediate representation, merges the sources
in layers (later sources override earlier ones), and lets the user read values
by key or extract them into their own struct.

The main line is:

```
multiple sources  →  one intermediate representation  →  layered merge
                  →  read by key / extract into a struct
```

Design constraints worth knowing before touching code:

- Integers keep full precision. The intermediate representation stores integers
  as `Int64`, not as a double, so large values survive the round trip.
- The core (`Value` and merge logic) does not touch I/O and must compile on every
  target. File and environment sources belong in separate subpackages.
- Extraction into user structs reuses the compiler's built-in `derive(FromJson)`;
  the library does not generate code or define custom derive traits.
- Error messages must name the key, the expected type, and the actual type.
- The module is split into packages: `MuVirus/moonfig/core` (core) and format
  sources under `MuVirus/moonfig/core/source/`, one directory per format.
  Leaving the alias off binds the directory name, which also compiles, but every
  `moon.pkg` here spells the alias out (`@config`, `@jsonsrc`) so the short name
  survives a future directory change.
- A package must not be named after a core package, not even when every import
  uses an explicit alias. The package name itself occupies a global name, so a
  package called `json` keeps `moonbitlang/core/json` from loading at all and
  its self-references fail to resolve. Keep the `_source` suffix.
- Methods cannot cross package boundaries (`4059: Cannot define method for
  foreign type`). A helper on another package's type has to be a free function:
  `to_json(v)`, not `v.to_json()`. Prefer free functions for anything that might
  end up in a different package later.

Read `docs/design.md` before implementing anything. `docs/roadmap.md` lists the
directions still to be built, each marked done, in progress or not started.
`docs/testing.md` is the test convention for this project.

Implemented today: the core package (`Value`, path lookup, merge, error
handling, `Config`, `MemorySource`, extraction into user structs) and three
source packages: `core/source/json_source` (`JsonSource`, `to_json`,
`extract_from`), `core/source/ini_source` (`IniSource`, hand-written parser)
and `core/source/dotenv_source` (`DotenvSource`, hand-written parser).

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

- The core package sits in `core/`; its sources sit in `core/source/`, one
  directory per format, and `docs/` holds the design, roadmap and testing
  documents.

- Tests follow `docs/testing.md`: examples for public API live in `///` doc
  comments as ` ```mbt check ` blocks, private logic goes into `_wbtest.mbt`,
  public API behaviour goes into `_test.mbt`. This project does not use inline
  tests.

- A pre-commit hook lives in `.githooks/pre-commit`; enable it once per clone
  with `git config core.hooksPath .githooks`.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.
