---
name: ios-app-e2e-verify
description: >-
  Runs MikeTodoList iOS UI tests (XCUITest) and verifies simulator builds after
  substantive Swift/SwiftUI/SwiftData changes, navigation or notification logic edits,
  or when the user asks for end-to-end verification. Trigger after multi-file refactors,
  model/schema updates, or before merging significant UI work in ~/src/mike_todo_list.
disable-model-invocation: false
---

# iOS app end-to-end verification (MikeTodoList)

## When to apply

Treat as **major** when any of these changed:

- Swift sources under `MikeTodoList/` (models, views, app entry, notifications)
- Xcode project/scheme, UI test bundle, or `scripts/run-ios-e2e.sh`
- Anything that can break launch, navigation, or Core Data/SwiftData persistence

Do **not** block on E2E for trivial copy or comment-only edits unless the user asks.

## What to run

From the repository root (`mike_todo_list`):

```bash
chmod +x scripts/run-ios-e2e.sh   # once if needed
./scripts/run-ios-e2e.sh
```

Optional: override simulator destination:

```bash
DESTINATION='platform=iOS Simulator,name=iPhone 15' ./scripts/run-ios-e2e.sh
```

If `xcbeautify` is installed, the script uses it for readable logs; otherwise raw `xcodebuild` output is shown.

## Failure handling

1. Re-run with the same destination;Simulator cold-start issues are rare but possible.
2. If UI tests fail, open `MikeTodoListUITests/MikeTodoListUITests.swift` and align selectors with accessibility labels (navigation titles, button labels).
3. Confirm `MikeTodoList` scheme includes the **MikeTodoListUITests** target under Test action.

## Relation to hooks

If `.cursor/hooks.json` runs this script on `afterFileEdit`, failures surface immediately after edits to app Swift files. That is optional automation; this skill still applies whenever major edits occur without hooks.
