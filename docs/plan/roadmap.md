# moonfig 路线图

记录「按什么顺序做、每部分做完能验收什么」，不是契约，可以随时改。

设计文档见 [docs/design/design.md](../design/design.md)。

状态分三档：✅ 已完成（进入维护）、🚧 进行中、⬜ 未进行。

---

## 核心　🚧

**方向**：配置只在内存里存在——统一表示、按键合并、按 key 取值。不接触任何外部环境，因此在所有 target 上都能编译。

- [x] `Value` / `ValueKind`：一份表示覆盖所有格式的配置值
- [x] 点号路径取值
- [x] 合并规则：按键合并、数组整体替换
- [x] `Config` 构建器与 `get_string` / `get_int` / `get_bool` / `get_float`
- [x] 错误处理：`MissingKey` / `TypeMismatch` / `ParseError`
- [x] 按结构体取值（`derive(FromJson)`）
- [x] Source 追踪：`origin_of` / `origins` 查某个键最终来自哪一层，见 [sources.md](../design/sources.md#来源追踪)
- [ ] 取值错误带上来源（`TypeMismatch` 现在还是三个字段）

**为什么还是进行中**：追踪已经落到 `Value` 和 `Config` 上，剩下的是把来源写进取值错误的消息里；这会改 `ConfigError` 的形状，等错误类型一起收口。

### 最初的推进顺序

| 步 | 内容 | 验收 |
|---|---|---|
| 1 | `value.mbt` + `error.mbt` | 构造几个 `Value`，`debug_inspect` 形状对 |
| 2 | `merge.mbt` | 嵌套 `Table` 验证「后覆盖前、表逐 key 合、数组整体换」 |
| 3 | `source.mbt` + `config.mbt` | 两个 `MemorySource` 合起来，`get_*` 取到值；缺 key 报 `MissingKey` |
| 4 | `core/format/json_format/` | `Json` 文本 → `Value`，`Int` / `Float` 按有无小数点分开 |
| 5 | `extract` | 大整数端到端不丢 |

第 1~3 步做完，库就能用了（只是目前只有 `MemorySource`）。第 4、5 步各是独立的增量。

---

## 多格式　🚧

**方向**：把各种格式的配置读成同一份 `Value`。格式之间可以自由替换，声明不用改。

- [x] JSON 文本（`core/format/json_format/` 包）
- [x] TOML（`core/format/toml_format/` 包，依赖 `moonbit-community/toml`）
- [x] YAML（`core/format/yaml_format/` 包，依赖 `moonbit-community/yaml`）
- [x] `.env` 文本（`core/format/dotenv_format/` 包）
- [x] INI（`core/format/ini_format/` 包）
- [x] XML（`core/format/xml_format/` 包，依赖 `Milky2018/xml`）
- [x] CBOR（`core/format/cbor_format/` 包，依赖 `2515050242/cbor`）

每加一种格式只做一件事：格式 → `Value`。合并、取值、校验都复用 `core/`，不为格式写第二套逻辑。

**格式说的是内容怎么写，Source 说的是从哪读。** `.env` 文件是一种格式，环境变量是一种 Source，两件事分开做：`EnvSource` 读环境变量时不需要知道它最后变成哪种格式。

**CBOR 是二进制格式，体积小，MCU 上常见。** 它也是检验 `Value` 表示能力的好例子——而这个检验的结果是：`Value` 原来少了一个形状。CBOR 有字节串，`Value` 原来没地方放它，所以 `ValueKind` 现在多了一个 `Bytes` 分支，`get_bytes` 把它原样取出来。其余的部分一一对得上：整数、字符串、数组、映射都不用特例。

**代价**：YAML、TOML、XML 和 CBOR 都依赖第三方解析器（`moonbit-community/yaml`、`moonbit-community/toml`、`Milky2018/xml`、`2515050242/cbor`），所以每种格式单独一个包，`moon.pkg` 写各自的 `import`，`core/` 和已完成的 `json_format`、`ini_format`、`dotenv_format` 不受影响。

**JSON、INI 和 `.env` 都是自己写的解析器，没有第三方依赖。** 三者都只用 MoonBit 标准库的包：JSON 走 `@json`，INI 和 `.env` 走 `@string` 里的 `parse_int64` / `parse_double`。INI 的类型猜法写在包的文档注释里：段落变层级、引号强制字符串、`;` 和 `#` 只在整行开头算注释；`.env` 的规则也写在包文档里：`export` 前缀可选、键名里的 `.` 变层级、单引号原样保留、双引号认转义、`#` 前面有空白才算行尾注释、不做变量展开。

**YAML 的语法交给 `moonbit-community/yaml`，本库只做 `Yaml` → `Value` 的转换。** 包文档写明了边界：只接受一个文档，空文件、空文档、只有注释的文件以及根节点为 `null` 的文件得到空表；根节点通常应是映射；整数超出 `Int64` 报错，不静默降级成浮点。

**TOML 的语法交给 `moonbit-community/toml`，本库只做 `TomlValue` → `Value` 的转换。** 包文档写明了边界：根节点必须是一张表；数组里混着不同类型时报错（TOML 要求同类型数组）；日期时间在 `Value` 里没有对应形状，按原文当字符串存；大整数保持 `Int64`。

**XML 的语法交给 `Milky2018/xml`，本库只做元素树 → `Value` 的转换。** XML 没有「键值」这回事，映射规则是本库定的，写在包文档里：根元素只是壳，子元素落在顶层；同名兄弟元素收成数组；属性在 `@` 前缀的键上；混合内容在 `#text` 上；CDATA 是字面文字，一定是字符串（这也是 XML 本身给「我要字符串」的办法）。

**CBOR 的语法交给 `2515050242/cbor`，本库只做 `CborValue` → `Value` 的转换。** 包文档写明了边界：根节点必须是一张映射；映射的键必须是文本字符串（CBOR 允许整数键，但配置里的键就是路径，路径是文本，整数键报错而不是偷偷转成字符串——那样整数键 `1` 会和字符串键 `"1"` 撞车）；标签被剥掉，只留里面的值（`Value` 没地方放标签）；`undefined` 报错（它和 `null` 不是一回事，`null` 落到 `Value::null()`）；字节串原样保留在 `Value::bytes` 里，`get_bytes` 取出原始字节；整数超出 `Int64` 报错，不静默降级成浮点；半精度和单精度浮点都展宽到 `Double`。

---

## 外部 Source　✅

**方向**：把外部世界读成配置。IO 只发生在这里，`core/` 那一层看不到文件和环境变量。

- [x] `FileSource`：读配置文件，格式交给上一层判断
- [x] `EnvSource`：读环境变量
- [x] `CliSource`：读命令行参数
- [x] 多个 Source 任意组合，优先级由加入顺序决定

### 环境变量是这一段里坑最多的

环境变量全是字符串：

- **类型推断必须在这一步做完**（`"5432"` → `Int`，`"true"` → `Bool`）。等到按结构体取值那步就晚了——标准库的 `Bool::from_json` 和 `Double::from_json` 都拒收字符串。
  - 落地方式：`core` 提供 `Value::from_literal`，`EnvSource` / `CliSource` 共用，不再各写一份。
- 分隔符约定要定：`_` 变 `.`？大小写敏感？
  - 落地方式：`_` 和 `.` 都算层级，键名统一转小写；只差大小写的两个变量落到同一个路径时报错。
- 前缀、空值、列表值怎么处理。
  - 落地方式：构造时给前缀（`EnvSource::all()` 读全部）；空值是空字符串；列表不拆，整串留作字符串。

---

## 校验　⬜

**方向**：配置读进来先验一遍，问题在启动时暴露，而不是在业务代码跑了一半才发现。

- [ ] 必填项缺失
- [ ] 取值范围校验（端口范围、字符串长度上限）
- [ ] 未知键是否报错，做成开关
- [ ] 校验规则由用户自己写
- [ ] 校验失败给出键名、期望值、实际值

---

## 自动发现格式　⬜

**方向**：给一个文件，不指定格式也能读进来。

- [ ] 按后缀判断（`.json` / `.toml` / `.yaml`）
- [ ] 后缀缺失或不可靠时按内容判断
- [ ] 判断失败时报错，并列出支持的格式
- [ ] 解析失败时给出位置和原因

---

## 热更新　⬜

**方向**：配置文件变了就重新生效，不必重启进程。

- [ ] 监听文件变化
- [ ] 重新读取并合并
- [ ] 通过回调通知使用方
- [ ] 新配置解析失败或校验不通过时保留旧配置，不让坏配置生效

---

## 依赖关系

```
核心 ──→ 多格式 ──→ 外部 Source ──→ 自动发现格式 ──→ 热更新
  │
  └──→ 校验
```

「校验」和「多格式」互不阻塞，可以先做任意一个。「自动发现格式」要等格式多于一种才有意义。

