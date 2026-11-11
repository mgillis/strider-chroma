# strider-chroma

Lighting control for the Razer Strider Chroma mouse mat (USB `1532:0c05`) on macOS.

By default the mat shows a fast rainbow travelling around its border, and
on a Mac there is nothing to change it with. `strider` is a small command line
tool that sets the colour, effect and brightness.

    strider warm -b 30        # dim, static warm white
    strider off
    strider 2040ff            # any hex colour
    strider breathe teal
    strider leds red blue     # gradient along the 19 LEDs
    strider brightness 50

Run `strider help` for everything else.

## Colours

`strider colors` lists the named colours with a description of how each one
looks on the mat. The names were calibrated by eye, because hex values are a
poor guide here: mixed colours look much less saturated on the mat than on a
screen, and a little of a second channel shifts the hue a long way. `ffb464`
is a peachy orange on a monitor and cream on the mat. `8c00ff` is purple on a
monitor and nearly magenta on the mat.

When a static colour changes, the mat fades from the old one to the new one
over a few seconds by itself. Per-LED patterns switch instantly, so
`strider leds <colour>` is the way to compare two colours back to back.

## Wave

`strider wave` is the factory rainbow, and `strider wave ccw` runs it the
other way. `--delay` sets its pace from 1 to 255, where higher is slower and
40 is the factory pace:

    strider wave --delay 255

The wave does not fade. It moves in discrete steps, which become visible at
high delays.

For `strider leds`, the first LED is at the power pack on the left edge. The
row runs anticlockwise seen from above: toward you, right along the front
edge, away along the right edge and back along the far edge. The last LED is
next to the first, and neighbouring LEDs blend in the diffuser, so the two
ends of a gradient mix where they meet at the power pack.

## Install

Needs Xcode or the Xcode command line tools (Swift 5.9 or later). No other dependencies.

    make install              # builds and copies strider to ~/.local/bin
    make install PREFIX=/usr/local

No driver, kernel extension or permission prompt is involved. The tool communicates
with the mat through IOKit's HID API as an ordinary user process.

## What survives a replug or sleep

Effects and brightness are sent with the protocol's "store" flag, and the mat
keeps them in its own memory. They are still in effect after the mat has lost
power, with nothing running on the Mac (confirmed on firmware v1.0).

Per-LED patterns (`strider leds`) are the exception: the mat cannot store
them. To keep one across a replug, or across a dock that switches off while
the Mac sleeps, install the background agent:

    strider agent install

This runs `strider watch` from login. It re-sends the last setting whenever
the mat is attached and whenever the Mac wakes. It is idle the rest of the
time. `strider agent status` shows whether it is running, and
`strider agent uninstall` removes it. Its log is
`~/Library/Logs/strider-chroma.log`.

The last setting is kept in
`~/Library/Application Support/strider-chroma/state.json`. Changes made with
`--temporary` are not recorded there, and the mat does not store them.

## How it works

The protocol is Razer's own, as documented by the
[OpenRazer](https://github.com/openrazer/openrazer) Linux driver, which
supports this mat. Every command is a 90-byte HID feature report sent to USB
interface 0, and the mat answers with a report of the same shape:

| offset | size | field |
| --- | --- | --- |
| 0 | 1 | status (0 in a request; 2 = success in a response) |
| 1 | 1 | transaction id (`0x3f` for lighting on this mat) |
| 2 | 2 | remaining packets |
| 4 | 1 | protocol type (0) |
| 5 | 1 | number of meaningful argument bytes |
| 6 | 1 | command class (`0x0f` for lighting) |
| 7 | 1 | command id |
| 8 | 80 | arguments |
| 88 | 1 | checksum: XOR of bytes 2 to 87 |
| 89 | 1 | reserved (0) |

Lighting commands in class `0x0f`:

| command | arguments | meaning |
| --- | --- | --- |
| `0x02` | store, led, effect, direction, speed, colour count, colours | set an effect: 0 off, 1 static, 2 breathe, 3 spectrum, 4 wave, 8 show the frame buffer |
| `0x03` | 0, 0, row, first column, last column, r g b per LED | fill the frame buffer (1 row of 19 LEDs) |
| `0x04` | store, led, brightness | set brightness, 0 to 255 |

Notes from testing against this mat (firmware v1.0):

- The brightness read command (`0x84`) is rejected, so the current brightness
  cannot be queried. `strider brightness` prints the last value it set.
- The control interface is the mouse-type HID interface. The mat's other two
  interfaces are keyboard-type, and macOS will not let a process open those
  without Input Monitoring permission. `strider` never opens them.

## Layout

- `Sources/StriderKit`: packet building and parsing, colours, the saved
  setting and argument parsing. No IOKit, so `swift test` runs without the mat.
- `Sources/strider`: the HID transport, the watcher, the launchd agent and the
  command line entry point.

## Licence

MIT. See [LICENSE](LICENSE).

This project is not affiliated with Razer. The protocol details come from
OpenRazer, which is licensed under GPL-2.0. No OpenRazer code is included here.
