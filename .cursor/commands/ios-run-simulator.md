# iOS Run (Simulator)

Boot an **iPhone Simulator**, build **MikeTodoList** (Debug), install it, and launch the app—without opening Xcode.

1. Resolve the repository root (folder containing `MikeTodoList.xcodeproj` and `scripts/run-ios-simulator.sh`). `cd` there if needed.

2. Execute:

```bash
chmod +x scripts/run-ios-simulator.sh 2>/dev/null; ./scripts/run-ios-simulator.sh
```

3. To use another simulator (must appear under **Available** in `xcrun simctl list devices available`), set **`SIMULATOR_NAME`**:

```bash
SIMULATOR_NAME='iPhone 17 Pro' ./scripts/run-ios-simulator.sh
```

Or pass a full **`DESTINATION`** like UI tests:

```bash
DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' ./scripts/run-ios-simulator.sh
```

4. On failure, distinguish simulator resolution vs build vs install/launch from `xcodebuild` / script output.
