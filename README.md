# Memo · 桌面日历本

macOS 上的一个本地小工具：桌面常驻一张「日历本」卡片，一天一页写总结、勾计划，一周一页做回顾。为**大小周**（有时上 6 天、有时 5 天）而设计。

原生 SwiftUI + WidgetKit，数据全部在本地，无账号、无网络。

![month](docs/shots/month.png)

## 环境要求

- macOS 14.0 及以上
- Xcode 26（或任意能编译 Swift 6 / SwiftUI 的 Xcode 15+）
- Homebrew（仅用于安装 XcodeGen）

## 安装

```bash
brew install xcodegen   # 只需一次
make run                # 生成工程 → 编译 → 安装到 ~/Applications → 启动
```

首次运行后，桌面右键 →「编辑小组件」→ 搜索 **Memo**，可以添加两种组件：

| 尺寸 | 内容 |
| --- | --- |
| 中号 | 当月月历，有记录的日子带小点，点开回到今天 |
| 大号 | 左侧月历 + 右侧「今天的计划」，**可以直接在组件里勾掉** |

## 使用

- **月**：默认显示当月。点任意一天打开当天页面；今天用朱红圈标出；工作日与休息日底色不同。
- **日**：上半是「总结」（整段文字，自动保存），下半是「计划」（可勾选清单，回车添加，拖动排序）。
- **周**：本周 7 天概览 + 「本周上班 N 天」设置（自动跟随大小周 / 手动指定）+ 统计 + 本周总结。
- **设置**：大周/小周天数、是否交替、锚点周、数据目录、按月导出 Markdown。

### 大小周怎么算

- 锚点周为大周，之后隔周交替：大周 = 周一到周六（6 天），小周 = 周一到周五（5 天），**周日永远休息**。
- 任何一周都可以手动覆盖（周页面的 `自动 / 4 天 / 5 天 / 6 天 / 自定义`），覆盖只影响那一周。
- 想改节奏：设置 → 锚点周 →「设为本周」。

### 深链

- `memo://today` — 回到今天
- `memo://day/2026-11-04` — 直接打开某一天

组件的点击都走这两个链接。

## 数据

```
~/Library/Application Support/Memo/
├── store.json          # 主数据（JSON，可手改）
├── store.json.bak      # 上一次写入的备份
└── export/YYYY-MM.md   # 按月导出的 Markdown
```

- 写入是「临时文件 → 原子替换」，并保留一份 `.bak`。
- 主文件损坏会自动从备份恢复；备份也坏了会把坏文件改名留档后重建空库。
- 只有真正写过内容的天/周才会落盘，清空即删除。

## 开发

```bash
make gen       # XcodeGen 生成 Memo.xcodeproj
make build     # 编译
make install   # 安装到 ~/Applications 并注册组件
make run       # build + install + 启动
make test      # 跑 Shared 层单元测试（日历算法 / 存储）
make doctor    # 检查安装状态、组件注册、数据目录
make clean
```

### 为什么组件要特殊签名

macOS 只把**带 `com.apple.security.app-sandbox` entitlement** 的扩展收录进插件库（`pkd`），否则它不会出现在小组件列表里。而本项目完全不签名（ad-hoc）、也不申请开发者账号，所以 `make install` 会：

1. 用 ad-hoc 身份签 widget 扩展，并附上 `app-sandbox` + `temporary-exception.files.absolute-path.read-write`（放行共享数据目录）
2. 再签外层 App
3. `lsregister` + `pluginkit -a` 注册

因为组件在沙盒里，`NSHomeDirectory()` 会被重定向到容器目录，所以共享路径统一由 `AppInfo.realHomeDirectory`（`getpwuid`）解析。

### 代码结构

```
Shared/           App 与 Widget 共用（编译进两个 target）
├── Models.swift        数据模型 + 视图快照
├── CalendarMath.swift  月网格 / ISO 周键 / 大小周工作日推导（纯函数，全测试覆盖）
├── StoreFile.swift     纯 IO：读写、原子替换、备份恢复、任务勾选
├── Store.swift         App 侧可观察仓库（300ms 防抖落盘）
├── Theme.swift         纸感手账配色与字体
├── PaperCard.swift     纸纹背景、卡片、细进度条
└── AppInfo.swift       共享路径
MemoApp/         月 / 日 / 周 / 设置四个页面
MemoWidget/      中号月历、大号月历+今日计划、组件内勾选 Intent
Tests/           CalendarMath / StoreFile / Store 单元测试
```

## 已知限制

- 不签名、不公证：只能本机使用，首次打开可能需要在「系统设置 → 隐私与安全性」里放行。
- 只看自己的 Mac：没有 iCloud 同步、没有 iPhone 版。
- 没有农历、法定节假日与调休；大小周完全按「交替规则 + 单周覆盖」推算。
- 组件内容不能直接打字（WidgetKit 限制），只能勾选；写文字要点开 App。
