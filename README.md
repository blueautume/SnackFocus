# SnakeFocus

自动贪吃蛇与专注休息伴侣的独立工作区。代码、字体、模拟数据、参考素材与开发预览均保存在本仓库中。

当前版本包含六张 16 × 24 地图、经典 / 现代两种蛇形态，以及禅意 / 舒缓 / 适中 / 激进四档速度，默认选择舒缓。开始前显示模拟预计用时，运行中锁定开局选项；铺满后提示休息。进行中重开需要像素确认，通关后直接返回开局。

界面及 VoiceOver 支持简体中文和英文，跟随系统或 iOS 的每 App 语言设置。所有中文语言变体使用简体中文，其他语言回退英文。英文速度为 Zen / Calm / Steady / Brisk，使用 Start、Restart 等简短按钮文案；品牌字样 `SNAKE` 保持不变。速度选项随可用宽度切换四列或两列，正文自然换行。详见[语言与文案说明](Docs/AutonomousSnake.md#语言与文案)。

## 打开项目

用 Xcode 打开 [SnakeFocus.xcworkspace](SnakeFocus.xcworkspace)，选择 `SnakeFocus` scheme 和 iPhone 模拟器即可运行。工程名和 scheme 为 `SnakeFocus`，最低支持 iOS 17。

应用名称、Bundle Identifier 和签名配置集中在 [Base.xcconfig](SnakeFocus/Configuration/Base.xcconfig)。真机运行时在 Xcode 中选择自己的开发团队。

## 目录

- `SnakeFocus/`：应用源码、中英语言资源、图标、像素字体及许可证。
- `SnakeFocus.xcodeproj/`：Xcode 工程和共享 scheme。
- `Tests/`、`Scripts/`：引擎、视觉、估时与本地化验证，以及模拟生成器。
- [Docs/AutonomousSnake.md](Docs/AutonomousSnake.md)：玩法、算法、地图、速度与验证说明。
- [Docs/Branding.md](Docs/Branding.md)：应用图标资源和生成提示词。
- [Docs/SnakeDurationSimulation.json](Docs/SnakeDurationSimulation.json)：六图每图 256 局的原始模拟步数、墙格和四档估时。
- [Docs/References](Docs/References/README.md)：用户提供的经典地图、蛇形态截图与原始录屏。
- [Docs/Previews](Docs/Previews/README.md)：按开发阶段归档的截图、录屏和动画预览。
- [Docs/WorkspaceOrigin.md](Docs/WorkspaceOrigin.md)、[复制清单](Docs/WorkspaceOrigin.json)：原始版本及文件 SHA-256。

## 验证

在本目录运行：

```sh
Scripts/check-snake-duration-estimates.sh
Scripts/check-snake-visuals.sh
Scripts/check-snake-localization.sh
```

修改引擎时还应运行 `Scripts/check-snake.sh`；算法或地图变化后使用 `Scripts/estimate-snake-duration.sh --write` 重新生成估时。

修改语言资源或界面文案后运行本地化检查，并在中英模拟器环境下检查开局、暂停、重开确认和休息提示的布局与 VoiceOver。

模拟器构建：

```sh
xcodebuild -workspace SnakeFocus.xcworkspace -scheme SnakeFocus \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/snakefocus-build \
  CODE_SIGNING_ALLOWED=NO build
```

## 版本来源

本仓库从 `icloudlab` 的 `experiment/snake-stationary-wave` 分支、提交 `5eb186d` 独立复制，保留该分支的开发历史。这里的 `main` 是贪吃蛇应用基线。Git 对象、工作目录和开局资料均独立保存；远程仓库尚未配置。
