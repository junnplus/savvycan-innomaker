# SavvyCAN InnoMaker Plugin

`innomakerusb2can` Qt CAN plugin for SavvyCAN on macOS.

This plugin is built on top of the macOS support files from [INNO-MAKER/usb2can](https://github.com/INNO-MAKER/usb2can/tree/master/For%20Mac%20Os/MAC-V1.2.0/Lib).

- Qt5 and Qt6 source compatibility
- classic CAN only
- supports bitrate setup, listen-only, loopback
- no CAN FD

## Build

Install the same Qt version used by SavvyCAN. For example, with Homebrew use `brew install qt@5`,
or point `QT_PREFIX` to the matching Qt installation.

Then build the plugin:

```sh
make SAVVYCAN_APP="/Applications/SavvyCAN.app"
```

`make` always removes `build/` first, so you do not need to clear CMake cache manually.


## Install Into SavvyCAN

Build output directory:

- `build/canbus/`

Copy that directory into your target `SavvyCAN.app` bundle:

```sh
mkdir -p "/Applications/SavvyCAN.app/Contents/PlugIns/canbus"
cp -R "build/canbus/." "/Applications/SavvyCAN.app/Contents/PlugIns/canbus/"
```

Then in SavvyCAN choose:

- `Connection`
- `Open Connection Window`
- `Qt Serial Bus Devices`
- device type `innomakerusb2can`
