# iOS E2E

Run end-to-end UI tests for **MikeTodoList** (XCUITest).

1. Resolve the repository root (this project is `mike_todo_list`). If the workspace root differs, `cd` to the folder that contains `MikeTodoList.xcodeproj` and `scripts/run-ios-e2e.sh`.

2. Execute:

```bash
chmod +x scripts/run-ios-e2e.sh 2>/dev/null; ./scripts/run-ios-e2e.sh
```

3. If the default simulator is missing on this machine, retry with an available iPhone simulator, for example:

```bash
DESTINATION='platform=iOS Simulator,name=iPhone 17,OS=latest' ./scripts/run-ios-e2e.sh
```

4. Summarize pass/fail from `xcodebuild` output. On failure, surface the first actionable error (build vs test, which test, simulator issues).

Optional: read `.cursor/skills/ios-app-e2e-verify/SKILL.md` for scope and when to run this outside the command.
