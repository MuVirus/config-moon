# 热更新

目标：配置文件改了，进程不重启也能用上新值；新文件写坏时继续用旧的。

## 快照

`Config::build` 把所有来源合并成一棵树，之后文件再改也不会变。`Config::build_live` 多保留一份来源清单和合并规则，返回 `LiveConfig`；每次重读都重新 `collect` + 合并，得到一棵完整的新树后再整体替换 `current`。

读者拿到的永远是完整快照，不会看到合并到一半的状态。旧快照上的来源信息也还在，不会被新快照改掉。

## 什么算变化

`LiveConfig` 只跟踪文件来源：

- 通过 `Source::raw_locator` 拿到可重读的 `Locator`，跟踪的是来源清单，不是最终合并树。被后面来源覆盖掉的文件也要能触发重读，否则改底层文件不会生效。见 [sources.md](sources.md#来源追踪)。
- 比较 `Locator::read` 读出的字节，不看 mtime。配置很小，直接比内容最稳；编辑器的「写临时文件再改名」也不会造成误判。
- 环境变量、命令行、内存来源没有可靠的变化事件，只能手动 `reload()`。

`build_live` 先记下文件基准，再合并第一份快照。这样文件如果在构建期间被改，下一次 `poll` 仍会看到差异，不会出现「快照已经是新内容、`current` 还是旧内容」的窗口。

## 一次 reload

1. 重新读所有来源的快照字节。
2. 重新 `collect` 并按原 `MergeRule` 合并。
3. 如果调用方给了规则表，先校验。
4. 全部成功才替换 `current`，同时推进快照基准。

任何一步失败，`current` 不动，旧配置继续用；快照基准也不推进，所以下一次 `poll()` 会继续尝试。`reload()` 把错误抛给调用方，`Watcher` 把它交给 `on_error`。

校验规则由调用方按需传入，例如 `live.reload(rules=[Rule::int_range("db.port", 1L, 65535L)])`。不传就只做读取和合并。

## 谁来轮询

`hot_reload/` 的 `watch` 只登记 `LiveConfig`、回调和建议间隔，返回 `Watcher`。真正的一轮检测由调用方通过 `Watcher::poll()` 驱动：

- 返回 `true` 表示检测到变化并尝试了 reload；reload 失败时返回 `false`，错误走 `on_error`。
- 返回 `false` 还表示文件没变、已经停止，或 reload 失败。
- 先替换快照，再回调，所以 `on_change` 里 `live.current()` 已经是新值。
- 回调自己抛错也只上报，不会把新快照退回去。
- `stop()` 之后不再检测、不再回调。

库不内建定时器：把定时器放进来意味着替调用方选定一个异步运行时，而不同 target 的运行时并不相同。`interval` 只是建议值，调用方可以用自己的定时器、事件循环或手动触发。以后接入 OS 文件事件时，`watch` 的用法可以保持不变。

## 失败与边界

- 只保留当前快照，没有历史版本；失败时是「继续用旧的」，不是「回退到上一版」。
- 不做多文件事务回滚：每个文件来源按自己的 `Locator` 重读，合并成功才切换。
- 不监听环境变量和命令行，因为没有可靠的变化事件。
- 不在检测到变化时强制校验，规则由调用方给。

## 位置

| 东西 | 位置 | 原因 |
|---|---|---|
| `LiveConfig`、`build_live`、`reload`、`poll` | [`core/live.mbt`](../../core/live.mbt) | 要碰 `Config` 私有字段；读文件走 `Locator`，不直接调平台 API |
| `Watcher`、`watch` | [`hot_reload/`](../../hot_reload/) | 回调与轮询句柄，不绑定运行时 |
| OS 文件事件 | 未来的 native 子包 | inotify / kqueue / ReadDirectoryChangesW 要平台 FFI |

`core/` 保持无平台代码；`hot_reload/` 只依赖 `core` 和标准库，所有 target 都能编译。

## 示例

[examples/hot_reload](../../examples/hot_reload/README.md) 用一次手动 `poll` 走完「没变 → 更新 → 坏配置 → 修好」四步。相关：[design.md](design.md#3-配置对象与取值) 说明合并与取值，[sources.md](sources.md) 说明 `Source` / `Locator`。
