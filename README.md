# AleCal v2.0

A modern, lightweight calendar for the macOS menu bar by SoftAI Yazılım. Written in Swift and SwiftUI with English and Turkish interface.

## What's New in Version 2.0

- **Refined Modern UI**: Glass styling, smooth hover states, cleaner typography, and balanced card layouts.
- **Multi-Colored Event Dots**: Days with events show dots in the actual colors of the respective calendars (up to 3 distinct colors per day).
- **Interactive Month & Year Quick Jumper**: Tap the month title to open a quick 12-month grid with year stepper to jump to any date instantly.
- **Relative Event Status Badges**: Live badges indicating "● Now" for meetings currently in progress, and "In 15m" / "In 30m" for upcoming events today.
- **One-Click Video Call Join**: Prominent join button supporting Zoom, Google Meet, Microsoft Teams, Webex, Slack Huddles, Discord, FaceTime, and more.
- **Fast Duration Presets**: Rapidly set 15m, 30m, 1h, 2h or All Day when creating new events.
- **Direct Build & Package Script**: One-click `./package_app.sh` script to build, ad-hoc sign, and install `AleCal.app` to `/Applications`.

## Requirements

- macOS 14 Sonoma, macOS 15 Sequoia, or macOS 27+
- Command Line Tools or Xcode 15+

## Quick Install / Build

```bash
cd /Users/darwin/Downloads/AleCal
./package_app.sh
```

This compiles an optimized release binary, packages the macOS `.app` bundle with high-resolution icons and localizations, signs it, and installs it into `/Applications/AleCal.app`.

## Features

- Menu bar icon with today's date (filled or outline style)
- Optional month, day of week, or custom date/time format next to the icon
- Option to hide the icon when text is shown
- Month grid with today highlight, selection rings, multi-color event dots, shaded weekends, and ISO week numbers
- Quick month and year selector
- Agenda view for 1 to 31 days with calendar colors, times, and locations
- Join button for video calls (Zoom, Meet, Teams, Webex, Slack, FaceTime, etc.)
- Quick event creation with duration presets
- Delete events (single or all future repeats) with confirmation
- Choose which calendars to show
- Global keyboard shortcut to open the calendar from any application
- Launch at login support
- Light, dark or system theme; small, medium or large text
- English and Turkish localizations, switchable on the fly

## Keyboard shortcuts in the calendar

| Key | Action |
| --- | --- |
| ← → | Previous or next day |
| ↑ ↓ | Previous or next week |
| ⌘← ⌘→ | Previous or next month |
| T | Jump to Today |
| ⌘N | New event on selected day |
| ⌘, | Preferences |
| Esc | Close popover |
| ⌘Q | Quit |

Double-click any day to add an event on it. Right-click the menu bar icon for Preferences and Quit.

## Project layout

```
project.yml                  XcodeGen project definition
package_app.sh               Automated build & installation script
Sources/
  AppDelegate.swift          App entry point
  StatusItemController.swift Menu bar item, popover, timers
  MenuBarIcon.swift          Draws the date icon
  CalendarView.swift         Month grid, month/year picker, agenda, toolbar
  EventRow.swift             Agenda row cards, meeting links, status badges
  NewEventView.swift         New event form with duration presets
  EventStore.swift           EventKit access & multi-color dots logic
  AppSettings.swift          Preferences storage
  Preferences.swift          Preferences window (General, Appearance, About)
  GlobalHotKey.swift         System-wide shortcut
  L10n.swift                 English and Turkish string lookup
Resources/
  en.lproj, tr.lproj         Localized strings
  Assets.xcassets            App icon set
  AppIcon.icns               Generated macOS icon
  Info.plist                 App bundle metadata & permissions
```

## Credits

AleCal is created by SoftAI Yazılım. AleCal's original feature set was inspired by Itsycal by Sanjay Madan (MIT licensed). AleCal contains no Itsycal source code, artwork or icons; all code and assets were developed from the ground up for AleCal.
