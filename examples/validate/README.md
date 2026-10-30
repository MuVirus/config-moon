# 校验示例

配置读进来先验一遍，问题在启动时暴露，而不是业务代码跑到一半才发现。

这个示例用一份写坏的配置演示两条用法：按键校验、提取到结构体后校验。两条路共用同一套规则和错误类型，只是约束写在哪里的区别。

运行：

```sh
moon run examples/validate
```

## 两条路怎么选

- **按键取值**：`Config` 上没有任何字段声明，规则必须显式写出来，路径是字符串。
- **提取到结构体**：字段已经在结构体里，约束跟着字段走，用 `Validate` 实现；提取后立刻校验，`prefix` 拼出完整路径。

两条路不互相替代。程序里只有零星几个键要验，用按键；已经提取成结构体、约束和字段一一对应，用 `Validate`。

## 按键：规则表

```moonbit
let rules = [
  Rule::int_range("db.port", 1L, 65535L),
  Rule::string_len("db.user", 1, 64),
  Rule::one_of("log.level", ["debug", "info", "warn", "error"]),
  Rule::allowed_keys("db", ["host", "port", "user"]),
]

cfg.validate(rules)      // 遇到第一个错误就停
cfg.validate_all(rules)  // 返回 Array[ConfigError]，一次列全
```

必填项不用单独写规则：任何规则取不到路径都会报 `MissingKey`，`get_*` 和 `extract_from` 本身也会报。

## 结构体：`Validate`

```moonbit
impl @config.Validate for DbCfg with fn validate(self, prefix) {
  @config.check_int_range(prefix.add("port"), self.port.to_int64(), 1L, 65535L)
  @config.check_string_len(prefix.add("user"), self.user, 1, 64)
}

let db : DbCfg = extract_validated_from(cfg, "db")
```

`extract_validated_from` 先走现有的 `extract_from`，再调结构体自己的 `Validate`。检查函数和按键校验共用，错误消息也一样。

## 未知键

`derive(FromJson)` 会忽略结构体里没有的字段，它不知道自己外面多了什么，所以未知键只能按键查：

```moonbit
Rule::allowed_keys("db", ["host", "port", "user"])
```

不写就不查，相当于开关默认关。嵌套结构要逐层给 `allowed_keys`；先不做递归 strict schema。

## 自定义规则

内置规则不够用时，返回 `None` 表示通过，`Some(实际值)` 表示失败：

```moonbit
Rule::custom("db.host", "non-empty and without spaces", fn(value) {
  match value.kind {
    ValueKind::Str(text) => if text.length() > 0 && !text.contains(" ") { None } else { Some(text) }
    _ => Some(value.kind.name())
  }
})
```

`实际值` 会进错误消息。密码这类字段别原样返回，只写长度或类型，避免漏进日志。

## 输出

`examples/validate/main.mbt` 里的配置故意写坏了：端口 70000、用户名为空、日志级别 `verbose`、`db` 下多了一个 `extra`。

```text
== 1. Validate by key: stop at the first error ==
invalid value for key 'db.port': expected 1..65535, got 70000

== 2. Validate by key: list every error ==
invalid value for key 'db.port': expected 1..65535, got 70000
invalid value for key 'db.user': expected 1..64 characters, got 0 characters
invalid value for key 'log.level': expected debug / info / warn / error, got verbose
key 'db.extra' is not allowed

== 3. Extract into a struct: constraints follow the fields ==
invalid value for key 'db.port': expected 1..65535, got 70000

== 4. Custom rules ==
passed
```

## 边界

- 校验只读合并后的结果，不改值；要修值应该在 Source 层做。
- 校验失败不自动回退到旧配置；热更新时要保留旧配置，由调用方决定。
- 未知键只按路径查，不做全局扫描：`allowed_keys("db", ...)` 只管 `db` 这一层。
- 错误消息不打印密码类字段的原值，规则自己负责脱敏。
