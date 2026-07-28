# rewire-crazyflie-example

[![Pixi Badge](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/prefix-dev/pixi/main/assets/badge/v0.json)](https://pixi.sh)

A **Crazyflie 2.1 Brushless** streaming IMU and AI-deck camera into [rewire](https://github.com/rewire-run/rewire),
via a patched [crazyswarm2](https://github.com/IMRCLab/crazyswarm2).

Unlike the other examples in this repo, this one drives **real hardware**.

## Topics

| Topic | Type | Rate | Notes |
|---|---|---|---|
| `/cf1/imu` | `sensor_msgs/Imu` | 50 Hz | Added by patch — crazyswarm2 has no built-in IMU topic |
| `/cf1/pose` | `geometry_msgs/PoseStamped` | 10 Hz | Orientation valid; position is not (see Limitations) |
| `/cf1/status` | `crazyflie_interfaces/Status` | 1 Hz | Battery, RSSI, supervisor state |
| `/camera/image` | `sensor_msgs/Image` | ~8 Hz | 324×244 `mono8` from the AI deck, over WiFi |
| `/camera/camera_info` | `sensor_msgs/CameraInfo` | ~8 Hz | Placeholder intrinsics (see Limitations) |
| `/tf` | `tf2_msgs/TFMessage` | 10 Hz | `world` → `cf1` |
| `/tf_static` | `tf2_msgs/TFMessage` | latched | `cf1` → `cf1/camera` |

Services: `/cf1/arm`, `takeoff`, `land`, `go_to`, `emergency`, `notify_setpoints_stop`,
`upload_trajectory`, `start_trajectory`, `add_logging`, `remove_logging`.

## Hardware

- Crazyflie 2.1 Brushless
- Crazyradio 2.0 or PA
- AI-deck 1.1 (optional — only for the camera topics)

## Setup

Requires [pixi](https://pixi.sh).

```bash
pixi run setup     # clone crazyswarm2 + motion_capture_tracking, apply patches/
pixi install       # build the ROS packages
```

`src/` is gitignored and fully reconstructed by `pixi run setup`, which pins both upstreams to a
known commit and applies `patches/`. Nothing in `src/` should be edited directly — change the patch.

## Usage

```bash
pixi run scan       # find the drone on the radio
pixi run server     # crazyswarm2 server (cflib backend)
pixi run camera     # AI-deck streamer (needs the deck's WiFi, see below)
pixi run viz        # rewire record --all
```

`pixi run server-cpp` runs the C++ backend instead. The `cflib` backend is recommended for
Brushless — it tracks Bitcraze's official library, which follows new hardware more promptly.

`crazyflie.rbl` is the saved Rerun blueprint: the camera view, the 3D scene with the camera frame
anchored to the drone, and the per-topic diagnostics table.

### Arming

Brushless requires an explicit arming step the brushed 2.1 does not:

```bash
ros2 service call /cf1/arm crazyflie_interfaces/srv/Arm "{arm: true}"
```

`scripts/arm_cycle.py --duration 5` arms for a fixed time then disarms, with the disarm in a
`finally` block. **Arming spins the props.**

## AI deck

The deck streams over **WiFi**, not the radio — it is a TCP socket to the GAP8, entirely
independent of CRTP. One-time setup:

1. Download `aideck_gap8_wifi_img_streamer_with_ap.bin` from the
   [aideck-gap8-examples releases](https://github.com/bitcraze/aideck-gap8-examples/releases).
   The `_with_ap` suffix is what makes it broadcast an access point.
2. Update the NINA/ESP32 firmware via the cfclient bootloader (~3 min) — install `cfclient` in a
   separate venv, not this environment.
3. Flash the GAP8 over the radio:
   ```bash
   cfloader flash aideck_gap8_wifi_img_streamer_with_ap.bin deck-bcAI:gap8-fw -w radio://0/80/2M/E7E7E7E7E7
   ```
   `cfloader` ships with **cfclient**, not cflib.
4. Power-cycle the Crazyflie — the GAP8 only boots new firmware on restart.
5. Join the open network **`WiFi streaming example`**, then `pixi run camera`.

`scripts/diagnose_camera.sh` captures everything about a streamer run to `/tmp/cfdiag/` — useful
because joining the deck's AP takes the machine off its normal network.

### Gotchas

- **The GAP8 serves one TCP client.** Probing the port with `nc` before starting the streamer can
  leave the deck unwilling to serve the next connection. Let the node be the first thing to connect.
- **macOS drifts back to a network with internet**, silently dropping the AP. Check with
  `ifconfig en0 | grep "inet "` — you want `192.168.4.x`.

## Patches

`src/` is upstream crazyswarm2 plus `patches/`:

| Patch | What |
|---|---|
| `0001-macos-build-fixes` | crazyflie-link-cpp's `Findlibusb.cmake` wants a static `libusb-1.0.a` on macOS, which conda-forge does not ship; conda's Eigen3 exports only the imported target, not `EIGEN3_INCLUDE_DIRS`; `crazyflie_cpp`/`crazyflieLinkCpp` were built but never installed |
| `0002-imu-default-topic` | Adds `imu` as a fifth `default_topic` alongside pose/scan/odom/status, in both the cflib and C++ backends. Converts g → m/s² and deg/s → rad/s |
| `0003-aideck-streamer-fixes` | Transposed `reshape(width, height)` produced a sheared image; `COLOR_BayerBG2RGBA` was applied to greyscale data; `image_height` was 324 when the HM01B0 is 244; publishes `mono8`; broadcasts the camera's static transform; publishes on receive rather than from a second timer, which was dropping ~⅓ of frames |
| `0004-pixi-build-manifests` | Per-package `pixi.toml` files — upstream ships none |
| `0005-mct-interfaces-manifest` | Same, for `motion_capture_tracking_interfaces` |

Patches 2 and 3 are upstreamable; 1 is macOS/packaging-specific; 4 and 5 exist only because this
build uses pixi-build-ros.

## Limitations

**No positioning deck.** With only the AI deck fitted there is no position reference, so
`stabilizer.estimator` is set to `1` (complementary) — Kalman diverges without one, reading tens of
metres while stationary. Consequently `/cf1/pose` orientation is valid but **position is not**, and
`takeoff` / `land` / `go_to` / `cmd_position` / `cmd_hover` are unusable. Yaw also drifts, since the
2.1 has no magnetometer. Fit a Flow deck v2, Lighthouse, Loco or mocap, then set `estimator: 2`.

**Camera intrinsics are a placeholder, not a calibration.** `fx`/`fy` are inherited from upstream's
324×324 values, `cx`/`cy` are the exact image centre, and distortion is assumed zero although the raw
image shows visible barrel distortion. Run `camera_calibration` at 324×244 before trusting
rectification or projection.

**The camera mount offset is an estimate.** `camera_translation` in `config/aideck_streamer.yaml` is
a guess for a top-mounted deck.

**IMU covariances are all zeros**, which `sensor_msgs/Imu` defines as "unknown". Fine for
visualization; an EKF needs real values, measured from ~60 s of stationary capture.

**`backend:=sim` does not work** — `crazyflie_sim` imports `cffirmware`, a separate SWIG build from
`bitcraze/crazyflie-firmware` that is not packaged here.

## Environments

| Environment | ROS Distro |
|---|---|
| `default` / `jazzy` | Jazzy |

Jazzy only, unlike the synthetic examples — crazyswarm2's C++ backend has distro-specific handling
and this has only been exercised on Jazzy.
