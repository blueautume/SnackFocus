# iOS Lab

一个通用 SwiftUI iOS 实验白板，最低支持 iOS 17。`main` 保持空白画布，每个实验从 `main` 创建独立分支。`blank-canvas` 标签标记最初的白板提交。

## 当前实验：蛇行 · 自动贪吃蛇专注伴侣

分支 `experiment/autonomous-snake-focus`，从空白 `main` 独立创建。

打开即自动运行第一张 **16 × 24 无边界地图**。机器人自行寻找随机食物，四边可环绕，逐步填满棋盘。你可以把手机放在一边开始工作，填满或碰撞结束后会出现休息提示，不会自动开下一局。

- 原生 Swift 提供「经典环路」与「动态环路」，默认动态。动态策略在进食后尝试重构安全闭环，无合适新路线时沿用旧环；两种策略在当前规则下均能逐步填满。
- 参考 Snake Xenzia 的简洁 LCD 风格：黄绿色底、黑色方格、点阵字形、步进画面；首页仅保留分数、计时、棋盘、暂停和重开。策略与节奏集中在设置，切换策略会重新开局。
- 三档节奏：舒缓 6 步/秒、平稳 10 步/秒、流动 16 步/秒；支持暂停、重开。
- 前台运行时保持屏幕常亮；暂停、暂时失活或进入后台时停止游戏和计时，恢复原有常亮设置。返回前台继续原局，不补跑后台步数；手动暂停会保持。
- 提醒仅在应用内出现；进程结束后，下次重新随机开局，不持久化存档。

这不是固定时长的番茄钟。运行时间取决于策略、食物、节奏、暂停和设备调度。算法的安全与填满性质限于本实验的单蛇、单食物、无障碍环绕地图。

方案、开源调研、算法不变量、界面与验证说明见 [Docs/AutonomousSnake.md](Docs/AutonomousSnake.md)。

### 验证命令

```sh
Scripts/check-snake.sh
# 扩展默认地图的种子数量：
SNAKE_DEFAULT_SEEDS=1000 Scripts/check-snake.sh

xcodebuild -project iOSLab.xcodeproj -scheme iOSLab \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Debug 构建支持模拟器检查参数 `--snake-preview-midpoint`、`--snake-preview-filled`、`--snake-preview-near-full` 和 `--snake-preview-last-bite`，分别展示半屏、满屏、接近满屏，以及自动吃掉最后一格后结束的过程。追加 `--snake-strategy-classic` 可检查经典策略。普通启动与 Release 构建不使用这些参数。

## 打开运行

1. 用 Xcode 打开 `iOSLab.xcodeproj`。
2. 选择 `iOSLab` scheme 和一个 iPhone 模拟器，点击运行。
3. 如需真机运行，在 target `iOSLab` 的 Signing & Capabilities 中选择自己的开发团队。

项目默认 Bundle Identifier 为 `com.lihao.ioslab`，应用显示名为 **iOS Lab**，包含 Debug 和 Release 两种构建配置。

名称、Bundle Identifier、开发团队和版本号集中在 `iOSLab/Configuration/Base.xcconfig`。项目已保留当前配置的开发团队，其他开发者可以在这里替换。

入口为 `iOSLab/iOSLabApp.swift`，白板页面为 `iOSLab/ContentView.swift`。主分支只显示纯白页面，无导航、功能入口或额外能力。

## 创建独立实验

先用 `git status` 检查工作区。已有实验如果有未提交改动，先在该实验分支提交，再切换分支。

回到空白主分支后创建实验分支，例如：

```sh
git switch main
git switch -c experiment/counter
```

把 `counter` 换成实际实验名称，即 `experiment/<name>`。只在准备实现对应功能时创建实验分支。

## 切换实验

回到空白画布：

```sh
git switch main
```

继续已有实验：

```sh
git switch experiment/counter
```

已有实验如果有未提交改动，先在当前实验分支提交，再切换：

```sh
git status
git add -A
git commit -m "保存当前实验进度"
git status --short
git switch main
```

提交前检查将要保存的文件；切换前确认 `git status --short` 没有输出，避免把未提交的文件带到另一个实验。

不同实验保持独立，**不要把实验分支合并回 `main`**。后续实验始终从 `main` 创建，避免带入其他实验的代码或配置。

## 实验配置与数据

根据实验需要，在对应分支增加 capability、entitlement、权限说明或依赖，并将配置与代码一起提交。

各分支默认使用相同 Bundle Identifier。切换 Git 分支只改变代码，不会清除模拟器或真机上已有的应用本地数据。若实验之间需要隔离数据，请自行清理应用数据、删除并重新安装应用，或为实验配置不同的 Bundle Identifier。
