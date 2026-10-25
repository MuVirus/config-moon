// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "MuVirus/moonfig"

version = "0.1.2"

readme = "README.mbt.md"

repository = "https://github.com/MuVirus/moonfig.git"

license = "Apache-2.0"

keywords = [
  "config",
  "configuration",
  "settings",
  "merge",
  "json",
  "yaml",
  "toml",
  "xml",
  "ini",
  "env",
  "cbor",
]

preferred_target = "native"

description = "MoonBit 原生配置库：一处声明，多来源汇入。"

import {
  "Milky2018/xml@0.6.1",
  "moonbit-community/toml@0.5.0",
  "moonbit-community/yaml@0.0.8",
  "2515050242/cbor@0.1.2",
  "moonbitlang/x@0.5.5",
}
