# Clockout

A native macOS app for tracking working hours, made for timesheets that only ask for *from*, *to* and *break*.

Start the timer, pause as often as you like, and finish the day. Clockout shows the actual work blocks and condenses them into the one line your timesheet needs: the start is the first start, the break is the sum of all gaps, and the end follows from start, working time and break, so the worked time always matches.

The app is available in English and German.

## Features

- **Timer** with any number of pauses per day, also in the menu bar. Quitting keeps the timer in the menu bar.
- **Timesheet line** per day with optional rounding (5, 10, 15 or 30 minutes), ready to copy.
- **Several jobs**, each with its own target (per day or per week), workdays, first day of work, rounding and picture.
- **Balance** per week, month and year, a total balance with an optional carry-over, and charts.
- **Days off**: vacation, sick days and public holidays. Holidays are built in for Germany (all states), Austria and Switzerland and are detected from your location on the first start. Work on a day off still counts.
- **Away detection**: if the Mac was idle or asleep while the timer ran, the app asks whether that time was a break.
- **Hints based on German working time law** (ArbZG): required breaks and the daily maximum.
- **Import** from CSV and Excel (.xlsx), **export** to CSV.
- **Backup and restore** of all jobs, rules and entries, for example to move to a new Mac.
- **Themes** inspired by well-known apps, light and dark, and a custom accent color.
- **Shortcuts and Siri**: start, pause, finish the day, ask for today's hours.
- **Update check**: shows when a newer release is available here on GitHub.

## Install

Download the latest `.dmg` from [Releases](../../releases), open it and drag Clockout into Applications.

The app is not notarized by Apple, so macOS asks the first time you open it. Right-click the app and choose *Open*, or go to *System Settings > Privacy & Security* and click *Open Anyway*.

Requires macOS 15 or later on Apple silicon or Intel.

## Build from source

1. Open `Clockout.xcodeproj` in Xcode 27 or later.
2. Run the *Clockout* scheme.

Builds are signed to run locally, which needs no Apple Developer account. To sign with your own team, create `Config/Local.xcconfig` (ignored by git):

```
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_IDENTITY = Apple Development
```

Run the tests with *Product > Test* or:

```
xcodebuild test -project "Clockout.xcodeproj" -scheme "Clockout" -destination 'platform=macOS'
```

Launch with `-demo` in a Debug build to get two weeks of sample data in memory, without touching your own entries.

`Distribution/build-dist.sh` builds the universal `.dmg` in `dist/` and checks its signature, entitlements and that it contains no personal data.

## Privacy

- All entries stay on your Mac, in the app's sandbox container. There is no account and no analytics.
- The location is used once to choose the public holidays of your region and is not stored. You can also pick the region by hand.
- Once a day the app asks the GitHub API for the latest release of this repository to offer updates. Nothing about you or your hours is sent, and the check can be turned off in Settings.

## Project layout

```
Clockout/               App sources (SwiftUI, SwiftData)
  App/                  App entry, menu bar mode, Shortcuts actions
  Models/               Sessions, jobs, statistics, holidays, ArbZG checks
  Services/             Timer, import and export, backup, reminders
  Views/                Today, History, Statistics, Settings and shared components
  Localizable.xcstrings English and German texts
ClockoutTests/          Swift Testing tests
Distribution/           DMG build script, entitlements and read-me
Config/                 Signing configuration
```

## License

[MIT](LICENSE)
