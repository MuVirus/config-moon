# 多来源配置示例

一个服务从四个地方读配置：默认值、配置文件、环境变量、命令行参数。后加的覆盖先加的，最后按路径取值，并且能问出每个值来自哪一层。

运行：

```sh
moon run examples/multi_source -- --log-level=debug
```

`examples/multi_source/config/app.json` 是那一层配置文件；环境变量由程序自己设上，只为让输出可复现，真实程序直接读进程里已有的环境变量。

## 场景

服务 `orders`，需要这些配置：

- `db.host`、`db.port`、`db.password`
- `log.level`
- `feature.debug`

四层来源，按加入顺序：

1. 默认值：`db.host = localhost`、`db.port = 5432`、`log.level = info`、`feature.debug = false`
2. 配置文件 `config/app.json`：`db.host = db.internal`，其余不动
3. 环境变量：`APP_DB_PORT = 6543`、`APP_DB_PASSWORD = ...`
4. 命令行参数：`--log-level=debug`

## 覆盖结果

- `db.host` 来自文件，盖掉默认值
- `db.port` 环境变量赢，文件里的 `5432` 被 `6543` 盖掉
- `db.password` 只有环境变量提供
- `log.level` 命令行赢
- `feature.debug` 没人覆盖，留在默认值

`get_string("db.host")` 得到 `db.internal`，`get_int("db.port")` 得到 `6543`，`get_bool("feature.debug")` 得到 `false`。

## 来源追踪

每个值都能回答「谁给的」：

- `origin_of("db.host")` → 文件来源，标签是 `file:examples/multi_source/config/app.json`；`origin.locator()` 可以重新读这个文件
- `origin_of("db.port")` → 环境变量来源，标签是 `env:APP_DB_PORT`
- `origin_of("log.level")` → 命令行来源，标签是 `cli:--log-level`
- `origin_of("feature.debug")` → 内存默认值

`origin_of` 返回的 `kind()` 可以直接模式匹配，用来分支；`path()` 给结构化的层级路径；`label()` 只用来展示和写错误消息，按需生成，不反解析。每个值只存一个指向来源对象的引用，不存 label 字符串。

`origins()` 能一次列出所有叶子路径和来源，适合做 `--print-config` 这类诊断命令：

```text
db.host        file:examples/multi_source/config/app.json
db.port        env:APP_DB_PORT
db.password    env:APP_DB_PASSWORD
log.level      cli:--log-level
feature.debug  memory
```

## 错误消息

取值失败的消息说清键名、期望和实际；要追来源，用 `origin_of` 单独问：

```text
key 'db.port': expected Int, got Str
origin_of("db.port") -> env:APP_DB_PORT
```

## 边界

- 环境变量全是字符串，类型推断在 `EnvSource` 这一层做完，不能拖到按结构体取值时
- 文件不存在报 `IoError` 并指出文件路径，内容坏了报 `ParseError`
- 同一层加两次，后加覆盖先加
- 合并规则默认 `LastWins`，也可以换 `FirstWins`、`ByKind`，或者传自定义函数
- 表节点（比如 `db`）的来源是「最后碰它的那层」，只有叶子路径的来源准确
- 数组整体替换，不按元素合并
