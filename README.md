# iOS Lab

一个通用 SwiftUI iOS 实验白板，最低支持 iOS 17。`main` 保持空白画布，每个实验从 `main` 创建独立分支。`blank-canvas` 标签标记最初的白板提交。

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
