# NoUpdate

Tired of macOS constantly asking you to update? NoUpdate is a tiny menu bar app that silently dismisses those update popups the moment they appear.

No settings, no config. Just runs in the background and stays out of your way.


## Requirements

- macOS 13 or later
- Accessibility permission (needed to interact with notifications)

## Install

Download the latest release from the [releases page](https://github.com/paul-nameless/no-update/releases), unzip, and move `NoUpdate.app` to `/Applications`. The build is signed and notarized, so it opens without warnings.

Open the app and grant Accessibility access when prompted. It starts scanning as soon as permission is granted, no relaunch needed. The app adds itself to login items by default; you can turn that off from the menu bar icon.

## Build from source

```sh
./build.sh
```

Then move `NoUpdate.app` to `/Applications`.

Note: source builds are ad-hoc signed, so after each rebuild you need to re-grant Accessibility access (remove and re-add the app in System Settings > Privacy & Security > Accessibility).
