# Source 与 package 布局

`Source` 是 `core/` 定义的 trait，只有一个方法：

```moonbit
pub(open) trait Source {
  fn collect(Self) -> Value raise ConfigError
}
```

实现 `Source` 的类型就是一层配置：`collect` 把外部数据读成一棵 `Value`，`Config::add` 收下它，按加入顺序合并。合并、取值、提取都复用 `core/`，不为格式写第二套逻辑。

## package 划分与命名

除 `MemorySource` 外，每个 `Source` 实现占一个 `core/source/xxx_source` package，解析器依赖写在自己的 `moon.pkg` 里。加一个实现只动这个 package，`core/` 不会因此多出第三方依赖或平台代码。

目录名固定带 `_source` 后缀，避免和 MoonBit 标准库的包重名，原因见 [decisions.md](../decisions/decisions.md#1-包名不能和-moonbit-标准库的包重名)。

## 什么时候用第三方解析器

没有硬性标准。解析器成熟、好用、不引入平台依赖，符合 `core/` 的设计约束，就直接用；没有合适的，或者格式简单、自己写更可控，就自己写。

TOML、YAML、XML、CBOR 用第三方解析器；JSON、INI、`.env` 是自己写的。

## 跨 package 的 API

方法不能跨 package，跨 package 的能力写成自由函数：`to_json(v)`、`extract_from(cfg, path)`。设计新 API 时能用自由函数就别用方法。记录见 [decisions.md](../decisions/decisions.md#2-方法不能跨包)。
