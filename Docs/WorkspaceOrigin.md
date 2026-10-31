# 独立工作区来源

SnakeFocus 从原 `icloudlab` 仓库的 `experiment/snake-stationary-wave` 分支复制，原始提交为 `5eb186d20a80095bf40f46079913b608e45cc128`（四档速度，默认舒缓）。

本仓库使用独立 Git 对象存储保留该分支完整祖先历史，当前分支命名为 `main`。复制后移除了原仓库 remote，并增加 `SnakeFocus.xcworkspace` 作为 Xcode 入口。生产源码、工程、字体、测试、脚本和原始估时数据与来源提交保持一致。README 与 AGENTS 已按独立应用工作区更新。

`AutonomousSnake.md` 中的实验分支名与 `ca75bcb`、`3a12a02` 等提交号记录了开发过程。`SnakeDurationSimulation.json` 中的模拟时间、基点提交与引擎哈希保留真实来源，可在本仓库历史中核对。四档速度使用原始模拟步数换算。

[WorkspaceOrigin.json](WorkspaceOrigin.json) 记录来源提交、原始跟踪文件 SHA-256，以及本次复制的参考图、视频和预览素材 SHA-256。素材索引见 [References](References/README.md) 与 [Previews](Previews/README.md)。

## 复制验证

- 34 个生产源码 / 工程 / 测试等原文件与来源提交 SHA-256 完全一致；另两份根目录说明按新工作区更新，原版仍保存在 Git 历史中。
- 31 份参考图、录屏和历史预览逐文件 SHA-256 校验通过。
- Git 无 remote、alternates、共享对象硬链接或外部 worktree，来源提交和原始模拟基点的祖先历史均已保留，仓库连通性检查通过。
- 已从当前目录通过 `SnakeFocus.xcworkspace` 完成 Debug 模拟器构建。
- 四档估时完整性检查与完整视觉检查均通过。
