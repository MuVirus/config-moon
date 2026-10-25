# 热更新示例

配置文件变了，不重启进程也能用上新值；新文件写坏时继续用旧的。

这个示例在 `_build/hot_reload_example.json` 里反复写配置，演示四件事：

1. `build_live()` 拿到第一份快照。
2. 文件没变时 `poll()` 返回 `false`，不回调。
3. 文件变了时先替换快照，再触发 `on_change`。
4. 新内容解析失败时 `on_error` 收到错误，`current()` 仍是旧快照；修好后继续更新。

运行：

```sh
moon run examples/hot_reload
```

## 谁在轮询

`watch()` 只登记 `LiveConfig` 和回调，不启动定时器。示例里手动调用 `watcher.poll()`，每一步的结果才可复现；真实程序用自己的定时器或事件循环调用同一个方法：

```moonbit
let watcher = @hot_reload.watch(
  live,
  interval=1000,
  on_change=fn(cfg) { show("on_change", cfg) },
  on_error=fn(error) { println("新配置没生效：\{error}") },
)

// 由调用方按时钟调用
watcher.poll()
```

`interval` 只是建议的间隔，实际节奏由调用方决定。这样库不绑定某个异步运行时，`core/` 和轮询逻辑在所有 target 上都能编译。

## 文件变化怎么判断

`poll()` 只比较文件来源读出的字节，不看 mtime。配置很小，直接比内容最稳；编辑器「写临时文件再改名」也不会造成误判。

被后面来源覆盖掉的文件也会被跟踪：跟踪的是来源清单，不是最终合并树。

## 失败时

`reload` 先读、再合并、需要时再校验，全部成功才替换 `current`。任何一步失败，旧快照继续用；失败期间快照基准不前进，所以下一次 `poll()` 会继续尝试。

只保留当前快照，没有历史版本，所以这里是「继续用旧的」，不是「回退到上一版」。

设计取舍见 [`docs/design/hot-reload.md`](../../docs/design/hot-reload.md)，完整代码见 [`main.mbt`](main.mbt)。
