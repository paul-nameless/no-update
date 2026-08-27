# NoUpdate

Tired of macOS constantly asking you to update? NoUpdate is a tiny menu bar app that silently dismisses those update popups the moment they appear.

No settings, no config. Just runs in the background and stays out of your way.

![NoUpdate icon](logo.png)

## Requirements

- macOS
- Accessibility permission (needed to interact with notifications)

## Install

Build:

```sh
./build.sh
```

Move `NoUpdate.app` to `/Applications`, open it, and grant Accessibility access when prompted.

Note: the build is ad-hoc signed, so after rebuilding you need to re-grant Accessibility access (remove and re-add the app in System Settings > Privacy & Security > Accessibility).
