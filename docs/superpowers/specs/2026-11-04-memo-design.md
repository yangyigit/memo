# Memo（日账）— macOS 桌面日历本 + 小组件 设计文档

- 日期：2026-11-04
- 状态：已确认（待实现）
- 目标平台：macOS 14.0+
- 使用者：仅作者本人（单机、无账号、无云同步）

## 1. 一句话定位

一个常驻 macOS 桌面的「日历本」：一天一页写总结、勾计划，一周一页做回顾，桌面小组件上直接看到当月日历和今天还剩哪些事情要做。

## 2. 范围

### 2.1 做

1. 月视图（默认首页，默认显示当月）
2. 日详情：当天的「总结」（多行文本）+「计划」（可勾选清单）
3. 周视图：本周 7 天概览、本周上班天数设置（大小周）、统计回顾、本周总结
4. 桌面小组件两种尺寸：中号（月历）、大号（月历 + 今日计划，可勾选）
5. 纸感手账视觉风格
6. 本地 JSON 存储 + 备份恢复 + Markdown 按月导出

### 2.2 明确不做（V2 再说）

农历、法定节假日与调休、提醒通知、iCloud 同步、iPhone/iPad 版、富文本、标签/情绪、全文搜索、开机自启、导出 PDF、主题切换（仅跟随系统明暗）。

## 3. 技术架构

### 3.1 技术栈

- Swift 6 + SwiftUI
- WidgetKit（widget extension）
- App Intents（组件内勾选计划）
- 部署目标 macOS 14.0（桌面可交互组件的下限）
- 零第三方运行时依赖，全部系统框架

### 3.2 工程与构建

- 工程由 **XcodeGen** 从 `project.yml` 生成，`.xcodeproj` 不入库（`make gen` 重建）。
- 两个 target：
  - `Memo`（`com.hengji.memo`）— SwiftUI App
  - `MemoWidget`（`com.hengji.memo.widget`）— `com.apple.widgetkit-extension` extension，嵌入 `Memo.app/Contents/PlugIns/`
- `Shared/` 目录下的源码同时编译进两个 target（不建 framework，省去签名与嵌入复杂度）。
- **不签名 / ad-hoc 签名**：
  - `CODE_SIGN_IDENTITY = "-"`，`CODE_SIGNING_REQUIRED = YES`（ad-hoc），无 Team
  - 两个 target 均 `ENABLE_APP_SANDBOX = NO`（关闭沙盒）
  - 不使用 App Group，App 与 Widget 通过同一个磁盘路径读写数据
- `Makefile` 目标：
  - `make gen` — xcodegen 生成工程
  - `make build` — `xcodebuild -scheme Memo -configuration Debug build`
  - `make install` — 拷贝产物到 `~/Applications/Memo.app`，`pluginkit -a` 注册 widget，`open` 一次
  - `make run` — build + install + 启动
  - `make test` — 跑 Shared 层单元测试（swift test 或 xcodebuild test）
  - `make clean`

### 3.3 风险与退路

**风险**：ad-hoc 签名的本地 App，其 widget extension 可能无法被系统注册（不出现在「编辑小组件」列表）。

**验证方式**：里程碑 ① 只做「空壳 App + 一个静态 widget」，先跑通 `make install` → 组件出现在列表 → 添加成功，再写业务代码。

**退路**（按顺序尝试）：

1. `pluginkit -a ~/Applications/Memo.app/Contents/PlugIns/MemoWidget.appex` 强制注册
2. App 拷到 `/Applications`（部分系统版本对 `~/Applications` 注册较弱）
3. 清理 `~/Library/Developer/Xcode/DerivedData` 与 `killall -KILL pkd`，重启 Dock
4. 若仍不可用：改用 Xcode GUI 打开工程、选 "Sign to Run Locally" 手动 Run 一次完成注册；再不可用则回报用户，降级为「MenuBarExtra 常驻卡片」方案（用户决策）

## 4. 数据层

### 4.1 存储位置

```
~/Library/Application Support/Memo/
├── store.json      # 主数据
├── store.json.bak  # 上一次成功写入的版本
└── store.json.corrupt-<timestamp>  # 数据损坏时的留档
```

选文件而非 SQLite：单用户、数据量小（一年 ≤ 数千条任务），JSON 可读可手改可备份，且两个进程共享读取最简单。

### 4.2 模型

```swift
struct Settings: Codable {
    var bigWeekDays: Int        // 默认 6（大周上班天数）
    var smallWeekDays: Int      // 默认 5（小周上班天数）
    var bigWeekAnchor: String   // 锚点周的 ISO 周键，该周为大周，默认取首次启动所在周
    var alternating: Bool       // 是否按大小周交替；false 时每周都取 smallWeekDays
}

struct Task: Codable, Identifiable {
    var id: UUID
    var text: String
    var done: Bool
    var createdAt: Date
}

struct DayEntry: Codable {
    var summary: String
    var tasks: [Task]
    var updatedAt: Date
}

struct WeekEntry: Codable {
    var workdaysOverride: Int?  // 手动覆盖本周上班天数
    var summary: String
    var updatedAt: Date
}

struct StoreData: Codable {
    var version: Int            // 当前 1
    var settings: Settings
    var days: [String: DayEntry]   // key: "2026-11-04"
    var weeks: [String: WeekEntry] // key: ISO 周键 "2026-W45"
}
```

**键设计**：日键 `yyyy-MM-dd`（本地时区）；周键 ISO 8601 周（周一起始）`yyyy-'W'ww`，跨年周（12/31 可能属于次年 W01）由 ISO 周历自然处理正确。

**懒创建**：只有真正写入内容时才创建 `DayEntry` / `WeekEntry`；清空即删除条目，不留空壳。

### 4.3 Store 行为

- 单例 `@Observable final class Store`，成员：`data: StoreData`、`url: URL`、`lastError: String?`
- 写操作（`updateDay`、`updateWeek`、`toggleTask`、`updateSettings`）统一走 `mutate { ... }` → 变更后 300ms 防抖落盘（避免打字时高频写盘），并在落盘后调用 `WidgetCenter.shared.reloadAllTimelines()`
- 原子写：写 `store.json.tmp` → `FileManager.replaceItemAt`；写前把现有文件复制为 `.bak`
- 读：解码失败 → 尝试 `.bak`；成功则在 UI 顶部提示「已从备份恢复」；仍失败 → 把坏文件改名留档，创建空库并提示
- Widget 侧只读：每次渲染时从磁盘解码（数据量小，可直接读），不持有长期缓存

### 4.4 日期与工作日算法（`CalendarMath.swift`）

纯函数、无 UI 依赖、可单测：

- `monthGrid(for month: Date) -> [GridDay]`：返回 42 格（6 周 × 7 天，周一为首日），每项含 `date`、`isInCurrentMonth`、`isToday`
- `isoWeekKey(for date: Date) -> String`（如 `"2026-W45"`）、`mondayOfWeek(containing:) -> Date`
- `workdays(inWeek monday: Date, settings: Settings, override: Int?) -> Int`：
  1. `override` 存在 → 用它
  2. `alternating == false` → `smallWeekDays`
  3. 否则按目标周与 `bigWeekAnchor` 的**周数差绝对值**取奇偶：`|diff| % 2 == 0` → `bigWeekDays`，否则 `smallWeekDays`（锚点周之前同样成立，因此锚点定在过去的任意大周即可）
- `workdayDates(inWeek monday: Date, workdays n: Int) -> Set<Date>`：从周一起取前 n 天，**上限 6 天，周日永远休息**
- `isWorkday(date:)` = 上述集合包含该日

**约束**：周首日固定为周一（与 ISO 周、大小周语义一致），不提供设置项。

## 5. 界面

### 5.1 结构

单窗口 App（`WindowGroup`，默认尺寸 900×640，最小 780×560），`windowStyle(.hiddenTitleBar)` + 纸底铺满，窗口背景与纸色一致（无灰白系统底色露边）。不提供多窗口、不做菜单栏常驻。

```
RootView
├── 导航：左侧窄栏（本月 / 本周 / 设置）+ 内容区
├── MonthView        （默认）
├── WeekView
├── SettingsView
└── .sheet → DayDetailView(date:)
```

### 5.2 月视图

- 顶部：月份大标题（衬线，如「十一月 2026」，数字衬线）、`‹` `›` 切换月份、`回到今天` 按钮、`本周` 快捷入口
- 星期表头：一 二 三 四 五 六 日
- 网格：6 行 × 7 列
  - 每格内容：日期数字（衬线）、左上角「非本月」淡化、右上角总结存在时的小墨点、底部一条细进度线（`完成/总数`）与数字（有任务时显示，如 `2/3`）
  - 今天：朱红细圈描边
  - 工作日：纸底略深；休息日（含周日）：背景淡化 + 数字灰
  - 悬停：卡片轻微浮起（阴影 + 1pt 上移）；点击 → 打开 `DayDetailView`
- 底部状态条：`本月 12 天有记录 · 计划 47/63 · 上班 22 天`（本月统计）

### 5.3 日详情（Sheet）

- 标题：`11月4日 星期三 · 上班日/休息日`（衬线大标题）
- `总结` 区：多行 `TextEditor`，纸底无边框，衬线可选（正文用系统无衬线，行高 1.6），右下角字数；停止输入 300ms 自动保存，保存后标题旁显示「已保存 HH:mm」
- `计划` 区：
  - 清单行：勾选框（朱红）+ 文本（勾选后划线 + 灰）+ 右侧删除按钮（悬停出现）
  - 底部「添加一项…」行：回车提交、Esc 退出编辑
  - 支持拖动排序；顶部显示 `2/3 完成`
- 顶部右侧：`‹ 前一天`、`后一天 ›`、`今天`（回到今天）
- 关闭 sheet 即落盘

### 5.4 周视图

- 标题：`2026 第 45 周 · 11月2日 – 11月8日`，上/下周切换、`本周` 按钮
- `本周上班` 设置器：分段控件 `5 天 / 6 天 / 自定义`，右侧小字说明当前来源（`跟随大小周规则` / `已手动设置`），点 `跟随规则` 清除 override
- 7 天列表：每行 = 星期 + 日期（休息日灰）+ 总结首行摘要（无则「—」）+ 计划完成数 `2/3`；点击进入日详情
- 统计行：`有记录 4 天 · 计划 9/12 · 上班 6 天 · 休息 1 天`
- `本周总结`：多行编辑器，自动保存逻辑同日详情

### 5.5 设置

- 大小周：大周上班天数（默认 6）、小周上班天数（默认 5）、`按大小周交替` 开关、锚点周（显示当前锚点周日期区间 + `设为本周` 按钮）
- 数据：`在 Finder 中显示数据目录`、`按月导出 Markdown`
  - 导出：`~/Library/Application Support/Memo/export/YYYY-MM.md`，格式为每天一节（`## 11月4日 星期三`、`总结` 原文、`- [x] 任务` 清单），月末尾附本周/本月无、仅当月内容
  - 导出完成后用 `NSWorkspace` 在 Finder 中选中该文件
- 关于：版本号、数据条数

## 6. 小组件

### 6.1 中号（`systemMedium`）

- 纸卡背景，标题「十一月 2026」+ 星期表头 + 月历网格（今天朱红圈、有记录的天小墨点）
- 页脚一行：`本周上班 6 天 · 今天 2/3`
- 点击任意位置 → `memo://today`

### 6.2 大号（`systemLarge`）

- 左 60%：同中号月历（点击某天 → `memo://day/2026-11-04`）
- 右 40%：「11月4日 · 今天的计划」清单，最多显示 5 项，每项一行，可**直接点击勾选**（`ToggleTaskIntent`，`AppIntent` + `Button(intent:)`）
  - 超出的显示 `+3 项`
  - 无计划时显示引导文案「今天还没有计划，点开写一条」
- 底部：`本周 9/12 · 上班 6 天`

### 6.3 刷新

- `TimelineProvider` 提供当前快照 + 30 分钟后的下一档（`TimelineReloadPolicy.after`）
- App 内每次落盘后 `WidgetCenter.shared.reloadAllTimelines()`
- `ToggleTaskIntent` 写入后同样触发 reload

### 6.4 深链

`MemoApp` 通过 `.onOpenURL` 处理：

- `memo://today` → 打开月视图并把选中日期设为今天
- `memo://day/2026-11-04` → 打开该日的 `DayDetailView`

## 7. 视觉系统（纸感手账）

### 7.1 颜色（`Theme.swift`）

| 用途 | 浅色 | 暗色 |
| --- | --- | --- |
| 纸底 | `#FBF7EF` | `#1C1A17` |
| 卡片浮起 | `#FFFDF8` | `#24211D` |
| 主文字 | `#2E2A24` | `#EDE6D8` |
| 次文字 | `#8B8272` | `#8A8272` |
| 分隔线 | `#2E2A24` @8% | `#EDE6D8` @10% |
| 朱红强调 | `#C2533D` | `#D9694F` |
| 休息日纸底 | `#2E2A24` @3% | `#EDE6D8` @4% |

用 `Color(light:dark:)` 通过 `NSColor(name:dynamicProvider:)` 实现动态色，跟随系统明暗。

### 7.2 纸纹背景（`PaperCard`）

`Canvas` 绘制，无图片资源：

1. 底色填充
2. 竖向 12pt / 横向 12pt 的 1px 网格线（alpha 0.03–0.05）
3. 200 个随机散点做纸纤维噪点（alpha 0.015，用固定 seed 保证渲染稳定）
4. 12pt 圆角 + 1px 内描边

### 7.3 字体

- 数字、月份与日期标题、周标题：`.system(size:, weight:, design: .serif)`（New York）
- 正文与清单：`.system(design: .default)`
- 层字间距：标题字距 +0.5，小标签字距 +0.8 且全大写感（中文用字重区分）

### 7.4 其他

- 卡片圆角 12，内边距 16–24
- 分隔线用发丝线（1px，非 2px）
- 进度一律细线条（2pt），不用实心色块
- 动效仅两处：sheet 出现、勾选计划的划线动画（0.15s）

## 8. 容错与边界

| 场景 | 处理 |
| --- | --- |
| store.json 损坏 | 读 `.bak` → 提示「已从备份恢复」→ 坏文件留档 |
| `.bak` 也损坏 | 留档为 `.corrupt-<ts>`，重建空库并提示 |
| 无数据目录 | 首次启动自动创建 |
| 同时多窗口/多进程 | 单 Store 单例；写盘用原子替换，Widget 只读 |
| 跨日使用中切换日期 | `NSCalendarDayChangedNotification` 或激活时刷新「今天」 |
| 跨年周 | ISO 周键天然正确 |
| 任务超长文本 | 单行截断显示，编辑器内换行 |
| 组件内点击过期数据 | Intent 每次执行前重新读盘，找不到任务则静默失败并 reload |

## 9. 测试

`Shared` 层纯逻辑必须单测（XCTest / Swift Testing）：

- `monthGrid`：月份首日/末日、跨月格、6 行固定、周一对齐
- `isoWeekKey`：普通日、12/31 跨年、1/1 跨年
- `workdays`：交替规则在锚点周/±1/±2 周的取值；override 优先级；`alternating == false`
- `workdayDates`：n=5 / 6 / 0 / 7（上限 6）时的日期集合
- `Store`：写入 → 重新解码一致；损坏文件走备份恢复；清空后条目被删除

UI 层手动验收清单（写在实现完成后逐条核对）：见 §10 里程碑 ⑥。

## 10. 里程碑

1. **工程骨架 + 组件注册验证**：XcodeGen 工程、`Makefile`、空壳 App + 静态 widget；跑通 `make install` 后组件能被添加。此步不通则先解决风险（见 §3.3）
2. **数据层**：`Models` / `CalendarMath` / `Store` + 单元测试
3. **App 页面**：月视图、日详情、周视图、设置
4. **小组件**：中号、大号、`ToggleTaskIntent`、深链
5. **视觉打磨**：纸纹、字体、明暗模式、动效
6. **装机验收**：安装后手动核对以下清单
   - 桌面添加中号/大号组件并正常渲染
   - 组件内勾选计划 → App 内状态同步
   - 改大小周设置 → 月历工作日底色、周视图统计同步变化
   - 写总结/计划后退出重开数据不丢
   - 深链从组件跳到对应日期
   - 明暗模式切换正常

## 11. 文件结构

```
memo/
├── Makefile
├── project.yml
├── .gitignore
├── README.md
├── Shared/
│   ├── Models.swift
│   ├── Store.swift
│   ├── CalendarMath.swift
│   ├── Theme.swift
│   └── PaperCard.swift
├── MemoApp/
│   ├── MemoApp.swift
│   ├── RootView.swift
│   ├── Views/MonthView.swift
│   ├── Views/DayDetailView.swift
│   ├── Views/WeekView.swift
│   ├── Views/SettingsView.swift
│   └── Info.plist
├── MemoWidget/
│   ├── MemoWidgetBundle.swift
│   ├── MonthWidget.swift
│   ├── TodayWidget.swift
│   ├── MonthGridWidgetView.swift
│   ├── ToggleTaskIntent.swift
│   └── Info.plist
├── Tests/
│   └── CalendarMathTests.swift / StoreTests.swift
└── docs/superpowers/specs/2026-11-04-memo-design.md
```
