# Quickshell Todo & Calendar Widget

A highly polished, fully animated, desktop-embedded Wayland widget for tracking tasks and calendar events seamlessly. Built for Hyprland and Quickshell with a native Catppuccin Mocha palette.

<p align="center">
  <img src="assets/demo.gif" alt="Quickshell Todo Widget Demo" width="600" style="border-radius: 12px;" />
</p>

> Building this in the open — if it saves you time, a star helps others find it.
> Found a bug, or have an idea? [Open an issue](https://github.com/ziuus/quickshell-todo/issues).
> New here? Start with a [good first issue](https://github.com/ziuus/quickshell-todo/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22).
> Theme, widget, and calendar-sync ideas welcome.

## Features
- **Ultra-Low Resource Footprint**: True **0.0% idle CPU** and **~26 MB RAM** via Vulkan rendering (`QSG_RHI_BACKEND=vulkan`) with static idle budget.
- **Smart Daily Habits Rollover**: Daily recurring tasks automatically reset and uncheck at midnight live without restarting the widget.
- **Hold & Slide to Delete**: Native swipe gestures with red reveal and spring snapback animations.
- **Keyboard Fast**: Press `Enter` to instantly add tasks and calendar events; `Ctrl+R` shortcut for daily habits.
- **Date & Time Picker**: Clickable trigger button opening an expandable inline drawer with upcoming date chips and time slots.
- **Dual Views & Icon Filters**:
  - **Tasks**: Filter by All, Active, Completed, or Daily recurring habits.
  - **Calendar**: Filter by Today, Upcoming, and All events with in-app Google Calendar sync.
- **Emerging Adaptive Card**: Smooth fluid spline transitions when resizing or expanding, paired with Wayland `Region` click-masking so clicks through unused areas pass directly to your desktop.
- **Wayland Native**: Runs on `WlrLayer.Bottom` directly on your desktop wallpaper behind active windows with zero-lag pointer handlers.
- **Catppuccin Styled**: Integrated Mocha tonal palette with Material Symbols Rounded icons.

## Requirements
- [Quickshell 0.3+](https://github.com/outfoxxed/quickshell)
- Python 3
- `Material Symbols Rounded` font installed on your system.

## Installation
```bash
git clone https://github.com/ziuus/quickshell-todo.git
cd quickshell-todo
./install.sh
```

## Usage
Run it with Vulkan hardware acceleration for minimal resource usage:
```bash
env QSG_RHI_BACKEND=vulkan qs -p ~/.config/quickshell-todo-widget/TodoWidget.qml -d
```
You can add this command to your `hyprland.conf` or window manager autostart file to launch it on boot.

## Configuration
To sync a remote calendar, create `~/.local/state/calendar_config.json`:
```json
{
  "ics_url": "https://calendar.google.com/calendar/ical/..."
}
```
