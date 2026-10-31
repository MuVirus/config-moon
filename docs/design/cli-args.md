# 命令行参数（CliSource）

`CliSource` 把进程的 argv 读成一棵配置树。它不经过 `Format`，也不碰文件；输入是参数表，输出是 `Layer`。
类型推断和 `EnvSource` 共用 `Value::from_literal`，规则见 [sources.md](sources.md#六种-source)。

## 输入与结果

| 输入 | 风格与声明 | 解析结果 |
|---|---|---|
| `--db.port=6543 --debug` | `Equals`（默认） | `db.port = 6543`、`debug = true` |
| `--db.port 6543 --debug` | `Separate` | `db.port = 6543`、`debug = true` |
| `--db.port=6543` | `Separate` | `ParseError`，不自动换风格 |
| `-p=5432 -vq` | `Equals` + 登记 `p→db.port`、`v→verbose`、`q→quiet` | `db.port = 5432`、`verbose = true`、`quiet = true` |
| `--tag a --tag b` | `Separate` + `with_array("tag")` | `tag = ["a", "b"]` |
| `--a=1 --a.b=2` | `Equals`（默认） | `ParseError`，不产出配置 |

短选项落到哪个路径由登记时指定，长选项的键名本身就是路径。下面各节解释这些结果为什么这样定。

## 一个来源只用一种取值风格

两种风格二选一，构造时定死；默认 `Equals`，用
`with_value_style(CliValueStyle::Separate)` 切到另一种：

- `Equals`（默认）：值跟在 `=` 后面，`--key=value`、短选项 `-p=value`。
- `Separate`：值是下一个参数，`--key value`、短选项 `-p value`。

不会同时生效。`Separate` 下写 `--key=value` 直接报 `ParseError`；`Equals` 下给登记过的短选项
写 `-p value` 也报错。

**为什么不做「两种都认」**：同一份 argv 里还有程序自己的参数，没有长选项登记表就无法判断
`--flag positional` 里的 `positional` 是值还是程序参数。风格固定后，切分是确定的，配置键不会
悄悄吃掉位置参数。`Equals` 下的 `--key value` 只能解释成「开关 + 位置参数」——裸 `--key` 在
两种风格里都是合法的布尔开关，不能把它当成错误。

**`Separate` 的边界**：以 `-` 开头的值会被当成下一个选项，负数请换 `Equals` 用 `--key=-1`；
单独一个 `-` 仍可当值。`--` 之后全部是位置参数。这个风格适合整条命令行都当配置的场景：
程序自己的 `--key=value` 也会报风格错误，可以放到 `--` 之后，或改用 `Equals`。

## 位置参数按声明映射

位置参数默认不进入配置；要让子命令、文件路径变成配置键，用 `with_positional(index, key)`
按「非选项参数」的顺序声明：

| 位置 | key |
|---|---|
| 0 | `command` |
| 1 | `model` |

```text
输入（Separate）：moonfmi simulate model.fmu --start 0 --stop 10 --step 0.01

结果：command = "simulate"、model = "model.fmu"、start = 0、stop = 10、step = 0.01
```

位置只数非选项参数：选项本身和它吃掉的值跳过，`--` 之后全部算位置参数。`new()` 不数可执行
文件名；`from_args` 默认把整张表都当参数，传 `program_name=true` 时跳过第 0 个。

默认 `Equals` 下 `--start 0` 只会得到 `start = true`，`0` 是位置参数，不会跟到选项后面；这种
CLI 要用 `Separate`。

没声明的位置不报错，也不生成空 key；同一个 key 被多个位置映射时后写的赢，声明成数组则按顺序
累加。位置值同样按字面猜类型：`model.fmu` 是字符串，位置上的 `0` 是 Int。

来源标签用原始 argv 下标（`cli:argv[1]`），不带值。需要位置参数的原始列表时，仍然读
`@env.args()` 或 `args` 字段。未登记短选项后面的值仍可能被算成位置参数，程序自己的参数建议
放到 `--` 后面。

## 短选项必须登记

`with_short_option` 登记收值的短选项，`with_short_flag` 登记布尔开关。没登记的短选项当程序
参数忽略。长选项没有登记表，`--key` 一律当配置参数，裸写就是开关。

取值写法跟着当前风格走，不再额外接受 `-p5432` 或另一种写法：一种风格只有一种切分方式。
布尔短选项可以连写（`-vq`）；开关不取值，要 false 用 `--no-key`。

**为什么要登记**：短选项太容易和程序自己的参数撞车，只有作者明确声明过的才当成配置。

## 重复参数要显式声明成数组

`with_array("tag")` 把路径声明成数组。声明后，同一个参数写几次就按顺序收进数组；只写一次也是
单元素数组。

**为什么不自动**：没声明过的重复键保持「后写的赢」，这是覆盖配置的常用写法。自动收数组会改变
已有语义。**为什么不一次吞多个值**：`--tag a b c` 和程序自己的位置参数无法区分；复数靠重复参数
表达。

数组和层级互相挡路（声明了 `tag` 又写 `--tag.x=1`）时报错，不猜哪个赢。

## 层级、冲突与来源

参数名里的 `-` 和 `.` 都拆成层级，键统一小写；`_` 是普通字符。

标量占了层级名，或数组被当成层级用时，报 `ParseError` 并点名参数，不静默丢值。

整层共用一个 site，按路径查回原始参数名；标签只写参数名、不写值，密码不会因为来源追踪漏进
日志。site 的接口见 [sources.md](sources.md#来源追踪)。

## 代码位置

实现在 `cli_source/`。`core/` 不碰 argv 和进程环境，所以这一层单独成包；包划分规则见
[sources.md](sources.md#package-划分与命名)。
