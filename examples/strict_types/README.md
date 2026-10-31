# 严格类型示例

配置值不会因为读取方便就换一种类型：数字来源只给数字，字符串来源只给字符串。这个示例用两份内容相同、只有 `db.port` 写法不同的 JSON，演示按键取值和结构体提取这两条路都会检查类型。

运行：

```sh
moon run examples/strict_types
```

## 两条读取路径

- **按键取值**：`get_int` 只接受 `Int`，`get_string` 只接受 `Str`，形状不符直接报错。
- **提取到结构体**：`NumericPort.port` 声明成 `Int32`，JSON 数字能映射；`TextualPort.port` 声明成 `String`，JSON 字符串能映射。两条路互不交叉。

```moonbit
struct NumericPort {
  port : Int32
  name : String
} derive(@json.FromJson)

struct TextualPort {
  port : String
  name : String
} derive(@json.FromJson)
```

## 输出

```text
== Read by key ==
numeric source get_int    -> 5432
string source  get_int    -> error: key 'db.port': expected Int, got Str
numeric source get_string -> error: key 'db.port': expected Str, got Int
string source  get_string -> 5432

== Extract into struct ==
numeric source -> NumericPort port = 5432, name = main
numeric source -> TextualPort error: key 'db.port': expected Str, got Int
string source  -> NumericPort error: key 'db.port': expected Int, got Str
string source  -> TextualPort port = "5432", name = main
```

输出可以分成两类：

- **按键取值**：只有同类型能通过；`get_int` 遇到字符串、`get_string` 遇到整数都会报错。
- **结构体提取**：`NumericPort` 只接受数字来源，`TextualPort` 只接受字符串来源，错误消息和按键取值一致。
- 因此同一份来源不可能同时满足两个结构体，必须按声明的类型选择来源。

## 边界

- 不做隐式转换：`"5432"` 不会自动变成 `5432`，`5432` 也不会自动变成 `"5432"`。
- 结构体字段用 `Int32` 时，JSON 数字按原生 `FromJson` 规则映射；需要超出 `Int32` 的整数时，用 `Int64Text` 并通过 `to_int64()` 取值。
- 错误消息只说键名、期望类型和实际类型，不会把值带进日志。

代码位置：[`main.mbt`](main.mbt)。
