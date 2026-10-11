# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## What this project is

`config-moon` is a configuration library for MoonBit. It reads configuration
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

Read `docs/design.md` before implementing anything; `docs/roadmap.md` has the
staged plan. Nothing is implemented yet.

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

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
