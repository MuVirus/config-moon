# 校验

配置读进来先验一遍，问题在启动时暴露，而不是业务代码跑到一半才发现。

两条路共用同一套规则和错误：

- **按键**：`Config` 上没有字段声明，规则表显式列出路径和约束。
- **结构体**：字段已经在结构体里，约束写在 `Validate` 实现里，提取后立刻跑。

两条路不互相替代：只有零星几个键要验，用按键；约束和字段一一对应，用 `Validate`。

## 按键

```moonbit
cfg.validate([
  Rule::int_range("db.port", 1L, 65535L),
  Rule::string_len("db.user", 1, 64),
  Rule::one_of("log.level", ["debug", "info", "warn", "error"]),
  Rule::allowed_keys("db", ["host", "port", "user"]),
])
```

`validate` 遇到第一个错误就停，和 `get_*` 一个口径；要一次列全用 `validate_all`，它返回
`Array[ConfigError]`，顺序和规则表一致。两个都带 `raise`：没 `build()` 时会现场合并，
读取或解析失败要报出来。

必填项不用单独写规则：任何规则取不到路径都会报 `MissingKey`。`get_*` 和 `extract_from`
本身也会报。

内置规则之外用 `Rule::custom`：返回 `None` 通过，`Some(实际值)` 失败。`实际值` 会进错误消息，
密码这类字段只写长度或类型，不原样返回。

## 结构体

```moonbit
impl @config.Validate for DbCfg with fn validate(self, prefix) {
  @config.check_int_range(prefix.add("port"), self.port.to_int64(), 1L, 65535L)
  @config.check_string_len(prefix.add("user"), self.user, 1, 64)
}

let db : DbCfg = extract_validated_from(cfg, "db")
```

`extract_validated_from` 先走 `extract_from`，再调结构体自己的 `Validate`。`prefix` 是提取时的
起始路径，拼上字段名就是完整路径，错误消息和按键校验一致。

## 未知键

`derive(FromJson)` 会忽略结构体里没有的字段，也不提供未知字段钩子，所以结构体不知道自己外面
多了什么。未知键只能按键查：

```moonbit
Rule::allowed_keys("db", ["host", "port", "user"])
```

不写就不查，相当于开关默认关。嵌套结构要逐层给 `allowed_keys`；递归 strict schema 暂不做。

## 错误

| 情况 | 错误 |
|---|---|
| 值不符合约束 | `InvalidValue(path, 期望约束, 实际)` |
| 出现没列出的键 | `UnknownKey(path)` |

```text
配置项 db.port 不符合约束：期望 1..65535，实际 70000
配置项 db.user 不符合约束：期望 1..64 个字符，实际 0 个字符
配置项 db.extra 不在允许的键里
```

`actual` 由规则给：类型不符时是形状名（`Str`），长度不符时是长度，自定义规则自己决定。
错误消息不打印密码类字段的原值。

## 边界

- 校验只读合并后的结果，不改值；要修值应该在 Source 层做。
- 校验失败不自动回退到旧配置；热更新时是否保留旧配置由调用方决定。
- 不给每个 `get_*` 加 `get_int_range` 之类的变体：API 会膨胀，同一份配置还会被反复检查。
- 不靠 `derive(FromJson)` 自动校验：派生的是标准库 trait，拿不到字段名、约束和未知键。
- 不做反射 / schema 自动映射：MoonBit 没有宏，最后仍要手写字段清单，不如直接写 `Validate`。

完整可运行的例子见 [`examples/validate`](../../examples/validate/README.md)。
