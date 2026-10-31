# SnakeFocus

- This is the dedicated, independent SnakeFocus workspace. `main` contains the runnable snake app.
- Xcode workspace: `SnakeFocus.xcworkspace`. Project and scheme: `iOSLab`.
- Entry point: `iOSLab/iOSLabApp.swift`. Main UI: `iOSLab/ContentView.swift`.
- Keep app code, assets, fonts, documentation and validation scripts self-contained in this repository.
- App identity and signing are configured in `iOSLab/Configuration/Base.xcconfig`.
- Preserve uncommitted changes before switching branches. Create branches according to the user's request.
- Validate source or project changes with an appropriate simulator build. Run the relevant checks in `Scripts/` when changing engine, rendering or duration estimates.
- Preserve the original simulation samples and provenance. When the engine changes, regenerate duration estimates with `Scripts/estimate-snake-duration.sh --write`.
- `Docs/References` contains user-supplied references; `Docs/Previews` contains historical development previews.
- After completing and validating work, create a local Git commit without waiting for an additional request. Do not push unless requested.
