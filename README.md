# Local Time

Local Time is a native, local-only macOS time tracker built with SwiftUI, SwiftData, and Swift Charts. It supports manual time entries, projects, a Monday–Sunday weekly goal, project distribution reporting, a menu-bar launcher, and CSV backup/restore.

## Requirements

- macOS 14 or newer
- Full Xcode with a matching macOS SDK selected via `xcode-select`

The current machine's standalone Command Line Tools compiler does not match its installed SDK, so builds will fail until Xcode or matching Command Line Tools are installed.

## Open and run

1. Open `LocalTime.xcodeproj` in Xcode.
2. Select the `LocalTime` app scheme and **My Mac** destination.
3. Run with **Command-R**.

From a matching command-line toolchain:

```sh
swift test
swift run LocalTime
```

Data is stored in the app's local SwiftData container. No account or network connection is used.

## CSV backup format

Use **Data → Export CSV Folder…** to create:

- `projects.csv`: `id,name,color_hex,created_at,updated_at,archived_at`
- `time_entries.csv`: `id,description,note,category,project_id,start_at,end_at,created_at,updated_at`

Dates use ISO-8601 with fractional seconds. Import validates both files before showing a preview, then upserts by UUID in one transaction. Legacy exports without the `category` column remain importable and use the `Other` category.
