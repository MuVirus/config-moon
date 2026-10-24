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
