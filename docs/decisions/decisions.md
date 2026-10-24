# 决策记录

记录已经踩过并定了结论的事。实测数据写清出处，结论写清代价。

## 1. 包名不能和 MoonBit 标准库的包重名

> **2026-09 实测：包名不能和 MoonBit 标准库的包重名，换别名也救不回来。**
> 格式 package 原本叫 `json/`，后来挪进 `core/source/` 时又试过叫 `json/`，两次都失败。
> 包名本身占一个全局名字：自己的包叫 `json`，`moonbitlang/core/json` 就根本加载不进来
> （`Package "json" not found in the loaded packages`），它的 `.mbti` 里 `@json.JsonPath`
> 这类自引用随之失效。把标准库那边的 import 写成 `@corejson` 也没用——冲突发生在包名，
> 不在别名上。结论：包名一律带后缀，避免撞名（`env` 会和 `moonbitlang/core/env` 撞，
> `file` 迟早也会撞上什么）。后缀写清包里提供什么：格式包 `_format`，Source 包 `_source`。
> 2026-10 格式包改成只提供 `Format` 后，后缀从 `_source` 改成 `_format`，撞名这个结论不变。

## 2. 方法不能跨包

> **2026-09 实测：方法不能跨包。**
> 跨包给别的包的类型加方法会报 `4059: Cannot define method for foreign type`。
> 所以 `Value::to_json` → `to_json(v)`，`Config::extract` → `extract_from(cfg, path)`。
> 自由函数不受影响（`extract(v)` 本来就是自由函数）。设计新 API 时要提前想清楚
> 哪些函数将来可能需要跨包——**能用自由函数就别用方法**。

## 3. `Value` 加 `Bytes` 分支

> **2026-10 决定：`Value` 加 `Bytes` 分支。**
> CBOR 是第一个会产出字节串的格式，而 `Value` 原来没有放字节串的地方。
> 加分支的机械成本很低：全库只有两处对 `ValueKind` 做穷尽匹配
> （`ValueKind::name` 和 `to_json`），`merge` / `get_path` / 各个 `get_*`
> 都只匹配自己关心的形状，不用改。加了之后 `Value` 才真的覆盖了所有格式的取值，
> 「提取到结构体」这条主线也不断——结构体里的 `Bytes` 字段能原样提取出来。

## 4. JSON 数值的边界

| 实测 | 结果 | 影响 |
|---|---|---|
| `@json.parse("9007199254740993")` | `Number(9007199254740992, repr=Some(9007199254740993))` | 超出精确整数范围时 `repr` 留着原文，靠它还原大整数 |
| `@json.parse("30")` / `@json.parse("1.5")` | `repr` 都是 `None` | **常见情况拿不到原文**，按有无小数点分的写法不成立 |
| `@json.from_json(@json.parse("\"1.5\""))` 到 `Double` | 失败 `Double::from_json: expected number` | 字符串自动转数字在 Json 层做不到 |
| `@json.from_json(@json.parse("\"true\""))` 到 `Bool` | 失败 `Bool::from_json: expected boolean` | 同上 |
| `@json.from_json(@json.parse("5432.7"))` 到 `Int` | 成功，得 `5432` | **静默截断**，不报错 |

> **2026-09 更正（实现时实测）**
>
> 上面第 1 行的结论只在「字面量超出 `Double` 精确整数范围（> 2^53 - 1）」时成立；
> 标准库在常见情况（`repr` 为 `None`）已经**不保留原文**了。所以 `convert.mbt` 改成：
>
> - `repr` 有值 → 原文在手，按 `Int64` 精确解析（`@bigint`）
> - `repr` 是 `None` → 只能看值：整数值且塞得进 `Int64` 就算整数，其余算浮点
>
> 代价：`1.0`、`1e2` 这种写了小数点／指数的整数值也按整数算。
> 反过来不会错——`5432` 一定是整数，不然 `get_int` 全都取不到。

## 5. CBOR 库的选择

| 实测 | 结果 | 影响 |
|---|---|---|
| registry 上的 CBOR 库 | `mizchi/cbor`（下载量最高）用的是旧的 `moon.mod.json`，当前工具链拒绝安装 | 只能从 `2515050242/cbor`（纯 MoonBit、零传递依赖、完整 RFC 8949）和 `f4ah6o/simple-webauthn/cbor`（同样零依赖，但是子集：不支持半精度/单精度浮点、不支持不定长容器、而且**静默忽略尾随字节**）里选 |

## 6. 来源追踪与合并规则

> **2026-10 实现时定的细节**
>
> - `Origin` 挂在 `Value` 的每个节点上，`Value` 的 `Eq` / `Debug` 都只看 `kind`。否则内容相同、来源不同的值不相等，合并测试会莫名其妙地失败。
> - `StringSource` / `BytesSource` 归到 `SourceKind::Custom`，标签分别是 `string` / `bytes`。它们既不是文件，也不是环境变量；给 `ByKind` 一个明确的档位比硬塞进 `Memory` 更清楚。
> - `ByKind(order)` 的数组按优先级从高到低写；没列出的 kind 排在最后。实现上按优先级**从低到高**处理来源，再用 `LastWins` 合并——同一档内后加的仍然赢。
> - `Custom(fn)` 收到的是「已经合好的部分」和「下一层」，返回新的部分。来源已经挂在值上，自定义函数要自己负责保留。
> - `Config::origin_of` / `origins` 保留 `raise ConfigError`：没 `build()` 时它们会现场合并，来源解析失败必须报出来，不能吞掉。路径不存在返回 `None`。
> - 取值错误暂时还没带上来源（`TypeMismatch` 仍是三个字段），等错误类型扩展后再补；现在先用 `origin_of` 查。

## 7. 文件、环境变量、命令行三个 source

> **2026-10 实现时定的细节**
>
> - 新增 `ConfigError::IoError(String)`：读不到外部数据（文件、环境变量）和「读到了但解析失败」是两回事，混进 `ParseError` 会让用户去查格式。消息以「读取失败：」开头，带路径或变量名。
> - `FileSource` 的路径就是 `String`，和 `moonbitlang/x/fs` 的接口一致；`Locator` 直接实现在 `FileSource` 自己身上，`origin_of` 拿到的 `locator` 调 `read()` 就能重新读出同一份字节。没有另外拍一个平台 `Path` 类型——那会把平台类型带进 core。
> - 环境变量和命令行都不是「字节 + 格式」，类型推断没法交给 `Format`。推断规则放进 core 的 `Value::from_literal`，两个包共用一份：`true` / `false` → `Bool`，整数 → `Int64`（超出范围报错），带小数点或指数 → `Float`，其余 → 字符串。dotenv 的推断没并过来，因为它要按行号报错，合并会丢掉行号。
> - `Config::attach_origin` 改成「已经有 origin 的节点不动」。环境变量、命令行的每个叶子在 `collect()` 里就标好了具体变量名/参数名，这一层不能被子来源标签盖掉；表节点仍由 `Config` 补。
> - `EnvSource` 只读指定前缀；`_` 和 `.` 都算层级，名字转小写。标量占了层级名、或两个变量落到同一个路径时报 `ParseError` 并点名两个变量——按 Map 遍历顺序猜赢家会让结果随平台变。变量名排序后才处理，保证同一份环境每次结果一致。
> - 环境变量的大小写冲突在 Windows 上测不出来：系统本身不区分大小写，`set_env_var` 会直接覆盖同名变量。碰撞检测仍在代码里，用白盒测试直接喂 `assign` 验证。
> - `CliSource` 只认长选项，位置参数和 `-x` 一律忽略——命令行上还有程序自己的参数。`--` 之后全部当位置参数。同一个键写两次后写的赢，但标量和层级互相挡路时（`--a=1 --a.b=2`、`--a.b=1 --a=2`）都报错，不静默丢值。
> - 命令行标签只写参数名（`cli:--db-password`），不写值：密码不该因为来源追踪漏进日志。
> - 新增的依赖 `moonbitlang/x` 手写进 `moon.mod`，没用 `moon add`（本仓库的约定）。

## 8. `String::compare` 先比长度

> **2026-10 实测：MoonBit 的 `String::compare` 不是字典序，长度不同的字符串先比长度。**
> `String::compare("z", "aa") < 0` 为真；`["db.host", "log.level", "feature.debug"].sort()` 得到
> 按长度递增的顺序，不是字母序。影响：任何「按名字排序」的展示都不能直接依赖 `sort()`，
> 需要字典序时得自己逐字符比较。环境变量的处理顺序只用它保证「确定」，不当作展示顺序。
