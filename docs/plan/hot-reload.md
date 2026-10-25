# 热更新

目标：配置文件改了，进程不重启也能用上新值；新文件写坏时继续用旧的。

## 一分钟用法

```moonbit
// 1. 和平时一样加来源，只是用 build_live() 而不是 build()
let live = Config::new()
  .add(FileSource::auto("app.json", detector))
  .add(EnvSource::new("APP_"))
  .build_live()

// 2. 业务代码只认当前快照
let cfg = live.current()
let port = cfg.get_int("db.port")

// 3. 想自己控制节奏就手动重读；失败会抛错，旧快照保留
live.reload()

// 4. 想自动跟文件变化就开一个 watcher
let watcher = @hot_reload.watch(
  live,
  interval=1000,
  on_change=fn(new_cfg) { println("配置已更新") },
  on_error=fn(error) { println("新配置没生效：\{error}") },
)

// 5. 退出前停掉
watcher.stop()
```

`build()` 把所有来源合并成一棵树，之后改文件也不会变；`build_live()` 多留一份来源清单，每次重读都重新 `collect` + `merge`。

`watch` 是自由函数而不是 `live.watch(...)`：方法不能跨 package，定时器又必须放在 `hot_reload`（见 [decisions.md](../decisions/decisions.md#2-方法不能跨包)）。

## 一次 reload 发生什么

1. 重新读所有 Source
2. 按 `MergeRule` 合并
3. 如果给了校验规则，先校验
4. 全部成功才替换 `current`

任何一步失败，`current` 不动，旧配置继续用。错误从 `reload()` 抛出，自动模式下交给 `on_error`。

读配置的人拿到的永远是一棵完整的树，不会看到合并到一半的状态。旧快照上的来源信息也还在，不会被新快照改掉。

## 文件变了怎么知道

`moonbitlang/x/fs` 只有读写，没有 mtime，也没有文件监听。所以第一版用轮询：

- 记住上次读到的字节，每隔 `interval` 重读一次，内容不同才算变化。
- 为什么不看 mtime：编辑器保存常用「写临时文件再改名」，时间戳精度和网络盘都不可靠；配置很小，直接比内容最稳。
- 只轮询文件类 Source。环境变量、命令行、内存 Source 没有变化事件，要更新只能手动 `reload()`。
- 默认 1 秒，和 Viper 一样。两次轮询之间的多次保存会合并成一次 reload。

`FileSource` 已经实现 `Locator`，重读就是再调一次 `read()`。

## 回调什么时候跑

- 启动时不回调，只有内容真的变了才回调一次。
- 先替换快照，再回调；回调里 `live.current()` 已经是新值。
- 回调抛错只上报，不会把新快照退回去。
- `stop()` 之后不再回调。停止必须显式调用。

## 坏配置不生效

`reload` 可以带规则表：

```moonbit
live.reload([
  Rule::int_range("db.port", 1L, 65535L),
])
```

校验不过就不替换，旧快照继续用。不传规则就只做读取和合并，不校验。

只保留当前快照，没有历史版本，所以失败时是「继续用旧的」，不是「回退到上一版」。

## 放在哪

| 东西 | 位置 | 原因 |
|---|---|---|
| `LiveConfig`、`reload`、`poll` | `core/` | 要碰 `Config` 私有字段；读文件走 `Locator`，不直接调平台 API |
| `watch`（定时器 + 回调循环） | `hot_reload/` | 需要 `moonbitlang/async` |
| OS 文件事件 | `hot_reload/` 的 native 子包 | inotify / kqueue / ReadDirectoryChangesW 要平台 FFI，后面补 |

第一版只做 `poll()`，由调用方驱动；`@hot_reload.watch` 是薄薄一层定时器。以后换成 OS 事件，`watch` 的用法不变。

## 成熟方案

| 方案 | 自动监听 | 失败时 |
|---|---|---|
| Viper（Go） | fsnotify，失败退回 1 秒轮询 | 保留旧值 |
| .NET | `reloadOnChange` + `IChangeToken` | 保留旧值 |
| Rust `config` | 手动 `refresh()`，监听交给 `notify` | 由调用方决定 |
| Nginx | SIGHUP 手动 reload | 解析成功才换 worker |

共同点：手动重读是地基，自动监听只是外面一层；坏配置不切换。

## 不做

- 不监听环境变量和命令行：没有可靠的变化事件。
- 不做版本历史、多文件事务回滚。
- 不在检测到变化时强制校验：规则由调用方给。
- 不把定时器和平台 API 放进 `core/`。

## 验收

- `reload()` 成功换快照；解析或 IO 失败时旧快照不变。
- 文件内容变了触发一次回调；没变不触发。
- 两次保存落在同一个间隔里只 reload 一次。
- `stop()` 后不再回调。
- `reload(rules)` 校验失败时保留旧快照。
- 轮询版所有 target 能编；`watch` 只在引入 async 的 target 提供。
