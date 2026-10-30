# iOS Lab

- Project and scheme: `iOSLab`. The entry point is `iOSLab/iOSLabApp.swift`; the blank view is `iOSLab/ContentView.swift`.
- `main` is the runnable blank template. The `blank-canvas` tag identifies the original starting commit.
- For each new feature experiment, create a local `experiment/<descriptive-name>` branch from `main`, never from another experiment branch. Continue on an existing experiment branch when the user requests work on that experiment.
- Keep experiment code, dependencies, capabilities and permissions in its own branch. Do not merge feature experiments into `main` unless explicitly requested.
- Before switching branches, inspect the working tree and preserve existing changes. Never discard changes to make switching easier.
- The base app is a white screen with no feature code, extra permissions or entitlements. Keep shared-template changes minimal.
- App identity and signing live in `iOSLab/Configuration/Base.xcconfig`. Add experiment-specific identity only when necessary for that experiment.
- Validate source or project changes with an appropriate simulator build. The main template has no behavior requiring a test target.
