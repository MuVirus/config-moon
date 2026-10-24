# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## What this project is

`moonfig` is a configuration library for MoonBit. It accepts configuration from
multiple sources (JSON, INI, `.env`, YAML, TOML, XML, CBOR, and in-memory
tables), normalizes every source into a single intermediate representation,
merges the sources in layers (later sources override earlier ones), and exposes
the result by key or by extraction into a user-defined struct:

```
multiple sources  →  one intermediate representation  →  layered merge
                  →  read by key / extract into a struct
```

### Design constraints

The following constraints apply to all code in this repository:

- **Integer precision.** Integers are stored as `Int64`, never as floating point.
- **The core is platform-independent.** It contains no platform-specific code
  and must compile on every target; file and environment sources are separate
  subpackages.
- **Struct extraction.** Extraction uses MoonBit's native `derive(FromJson)`;
  MoonBit currently supports neither deriving third-party traits nor macros.
- **Error messages.** Every message names the key, the expected type and the
  actual type.
- **Package layout.** `core/` plus one package per format under `core/source/`;
  always write import aliases explicitly (`@config`, `@jsonsrc`).
- **Package names.** Never name a package after a core package; format packages
  keep the `_source` suffix.
- **Cross-package helpers.** Methods cannot cross packages (`4059`); use free
  functions such as `to_json(v)`.

### Documentation

Documents live in `docs/`. Where each one goes and what belongs in it is in
[`docs/AGENTS.md`](docs/AGENTS.md).

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

- The core package sits in `core/`; its sources sit in `core/source/`, one
  directory per format. The documents live in `docs/`; see
  [`docs/AGENTS.md`](docs/AGENTS.md).

- Tests follow `docs/conventions/testing.md`: examples for public API live in `///` doc
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
