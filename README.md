# iOS Lab

一个通用 SwiftUI iOS 实验白板，最低支持 iOS 17。`main` 保持空白画布，每个实验从 `main` 创建独立分支。`blank-canvas` 标签标记最初的白板提交。

## 当前实验：蛇行 · 动态环路专注伴侣

分支 experiment/autonomous-snake-focus，从空白 main 独立创建。

进入后先选地图和速度，看到各档速度对应的模拟预计时长，点击「开始游戏」后才运行。只提供动态环路策略；运行中锁定速度、隐藏设置入口。铺满后停止并提醒休息；重开必须通过像素确认框，再回到选择页。

- 六张经典风格地图，全部为 16 × 24：无边原野、四面围墙、双横杠、交错隔墙、双竖栏、多层通道。墙壁实际占用棋盘格，缩略图与实战采用相同的墙块样式。
- 选择页仅显示地图缩略图、舒缓 / 适用 / 激进三档速度和对应分钟范围，默认无边、适用。实际速度为 6 / 10 / 16 步每秒，每图 256 局生产模拟生成 P10–P90 常见分钟范围，不是倒计时。
- 连续像素蛇身、方向眼睛、尖尾、摆动与食物呼吸。中文选择页、暂停 / 继续 / 重开按钮、提示和确认框统一使用像素字体与矩形效果。
- 暂停或离开会冻结游戏、计时与动画；返回不补跑。前台运行保持常亮，暂停 / 结束后恢复。
- 无联网或通知权限，提醒仅在应用内，进程退出不恢复游戏。

方案、模拟结果、字体来源和验证见 [Docs/AutonomousSnake.md](Docs/AutonomousSnake.md)。原始数据见 [Docs/SnakeDurationSimulation.json](Docs/SnakeDurationSimulation.json)。

### 验证

    Scripts/check-snake.sh
    Scripts/check-snake-visuals.sh
    Scripts/check-snake-duration-estimates.sh

更改地图或算法后重新模拟：

    Scripts/estimate-snake-duration.sh --write

模拟器构建：

    xcodebuild -project iOSLab.xcodeproj -scheme iOSLab \
      -configuration Debug -sdk iphonesimulator \
      -destination 'generic/platform=iOS Simulator' \
      CODE_SIGNING_ALLOWED=NO build

Debug 可用 --snake-map=courtyard --snake-preview-shape 检查围墙地图。普通启动不自动运行，全部预览参数只对 Debug 生效。

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
