<h1 align="center">
  <a href="https://rewire.run/">
    <img alt="banner" src="https://github.com/user-attachments/assets/4859413d-89b2-424c-a378-8a15260de384">
  </a>
</h1>

<p align="center">
  <a href="https://pixi.sh">
      <img alt="Powered by" src="https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/prefix-dev/pixi/main/assets/badge/v0.json"/>
  </a>
</p>

A Crazyflie 2.1 Brushless streaming IMU and AI-deck camera to [rewire](https://github.com/rewire-run/rewire), via a patched [crazyswarm2](https://github.com/IMRCLab/crazyswarm2).

Unlike the other examples in this repo, this one drives **real hardware**: a Crazyflie 2.1 Brushless, a Crazyradio 2.0 or PA, and — for the camera topics only — an AI-deck 1.1.

## Topics

| Topic | Type | Rate | Description |
|---|---|---|---|
| `/cf1/imu` | `sensor_msgs/Imu` | 50 Hz | Accelerometer and gyro, m/s² and rad/s. Added by patch — crazyswarm2 has no built-in IMU topic |
| `/cf1/pose` | `geometry_msgs/PoseStamped` | 10 Hz | Orientation valid, position is not (see Limitations) |
| `/cf1/status` | `crazyflie_interfaces/Status` | 1 Hz | Battery, RSSI, supervisor state |
| `/camera/image` | `sensor_msgs/Image` | ~8 Hz | 324x244 `mono8` from the AI deck, over WiFi |
| `/camera/camera_info` | `sensor_msgs/CameraInfo` | ~8 Hz | Placeholder intrinsics (see Limitations) |
| `/tf` | `tf2_msgs/TFMessage` | 10 Hz | `world` to `cf1` |
| `/tf_static` | `tf2_msgs/TFMessage` | latched | Static transform: `cf1` to `cf1/camera` |

Services: `/cf1/arm`, `takeoff`, `land`, `go_to`, `emergency`, `notify_setpoints_stop`,
`upload_trajectory`, `start_trajectory`, `add_logging`, `remove_logging`.

## Setup

Requires [pixi](https://pixi.sh).

```bash
pixi run setup
pixi install
```

`pixi run setup` clones crazyswarm2 and motion_capture_tracking at pinned commits and applies
`patches/`. `src/` is gitignored and fully reconstructed by that task — it is not vendored.

This project uses [pixi-build-ros](https://github.com/nicross/pixi-build-ros) to build the crazyswarm2
ROS packages as conda dependencies. Upstream ships no `pixi.toml` files, so `patches/0004` and
`patches/0005` add them.

## Environments

| Environment | ROS Distro |
|---|---|
| `default` / `jazzy` | Jazzy |

Jazzy only. crazyswarm2's C++ backend has distro-specific handling and this has only been exercised
on Jazzy.

## Usage

```bash
pixi run scan       # find the drone on the radio
pixi run server     # crazyswarm2 server, cflib backend
pixi run camera     # AI-deck streamer, needs the deck's WiFi
```

In a separate terminal, run rewire to visualize all topics in Rerun:

```bash
pixi run viz        # rewire record --all
```

`crazyflie.rbl` is the saved blueprint: camera view, 3D scene with the camera frame anchored to the
drone, and the per-topic diagnostics table.

`pixi run server-cpp` runs the C++ backend instead. `cflib` is recommended for Brushless — it tracks
Bitcraze's official library, which follows new hardware more promptly than crazyflie_cpp.

### Arming

Brushless requires an explicit arming step the brushed 2.1 does not. **Arming spins the props.**

```bash
pixi run ros2 service call /cf1/arm crazyflie_interfaces/srv/Arm "{arm: true}"
```

`scripts/arm_cycle.py --duration 5` arms for a fixed time then disarms, with the disarm in a
`finally` block so a failure mid-cycle still disarms.

## Development

`src/` is a clean upstream checkout plus `patches/`. **Never edit `src/` directly** — it is reset by
`pixi run setup`. To change behaviour:

```bash
# edit src/crazyswarm2/... , then regenerate the relevant patch
git -C src/crazyswarm2 diff -- <paths> > patches/000N-<name>.patch

pixi clean --build && pixi install
```

`pixi install` alone **silently skips rebuilding** edited source packages — it reports success, no
`.conda` artifact is produced, and the stale copy stays in `.pixi/envs/`. Always `pixi clean --build`
first, then verify the change landed:

```bash
grep -c "<something new>" .pixi/envs/default/lib/python3.12/site-packages/<pkg>/<file>.py
```

## How it works

Two independent data paths:

- **Radio (CRTP over USB)** — the crazyswarm2 server talks to the drone through the Crazyradio and
  publishes `/cf1/imu`, `/cf1/pose`, `/cf1/status` and `/tf`. Works on any network.
- **WiFi (TCP)** — `aideck_streamer.py` connects to the GAP8 on the AI deck at `192.168.4.1:5000` and
  publishes `/camera/image` and `/camera/camera_info`. Requires joining the deck's own access point.

The two are unrelated at the transport level; either runs without the other. `/tf_static` bridges
them, anchoring the camera frame to the drone body so the image has a pose.

Firmware log blocks hold **26 bytes**, which shapes what the IMU topic can carry: six `float32`
(accel + gyro) is 24 bytes, leaving no room for the attitude estimate. `/cf1/imu` therefore sets
`orientation_covariance[0] = -1`, the `sensor_msgs/Imu` convention for "this field is not produced".

## AI deck

The deck streams over WiFi, not the radio. One-time setup:

1. Download `aideck_gap8_wifi_img_streamer_with_ap.bin` from the
   [aideck-gap8-examples releases](https://github.com/bitcraze/aideck-gap8-examples/releases). The
   `_with_ap` suffix is what makes it broadcast an access point.
2. Update the NINA/ESP32 firmware via the cfclient bootloader (~3 min). Install `cfclient` in a
   separate venv — `opencv-python` conflicts with it, and this environment needs opencv.
3. Flash the GAP8 over the radio (`cfloader` ships with **cfclient**, not cflib):

   ```bash
   cfloader flash aideck_gap8_wifi_img_streamer_with_ap.bin deck-bcAI:gap8-fw -w radio://0/80/2M/E7E7E7E7E7
   ```

4. Power-cycle the Crazyflie — the GAP8 only boots new firmware on restart.
5. Join the open network **`WiFi streaming example`**, then `pixi run camera`.

`scripts/diagnose_camera.sh` captures a full streamer run to `/tmp/cfdiag/`, which is useful because
joining the deck's AP takes the machine off its normal network.

### Gotchas

- **The GAP8 serves one TCP client.** Probing the port with `nc` before starting the streamer can
  leave the deck unwilling to serve the next connection. Let the node connect first.
- **macOS drifts back to a network with internet**, silently dropping the AP. Check with
  `ifconfig en0 | grep "inet "` — you want `192.168.4.x`.

## Patches

| Patch | What |
|---|---|
| `0001-macos-build-fixes` | crazyflie-link-cpp's `Findlibusb.cmake` wants a static `libusb-1.0.a` on macOS, which conda-forge does not ship; conda's Eigen3 exports only the imported target, not `EIGEN3_INCLUDE_DIRS`; `crazyflie_cpp` and `crazyflieLinkCpp` were built but never installed |
| `0002-imu-default-topic` | Adds `imu` as a fifth `default_topic` beside pose/scan/odom/status, in both the cflib and C++ backends |
| `0003-aideck-streamer-fixes` | Transposed `reshape(width, height)` produced a sheared image; `COLOR_BayerBG2RGBA` was applied to greyscale data; `image_height` was 324 when the HM01B0 is 244; publishes `mono8`; broadcasts the camera's static transform; publishes on receive rather than from a second timer, which was dropping ~1/3 of frames |
| `0004-pixi-build-manifests` | Per-package `pixi.toml` files — upstream ships none |
| `0005-mct-interfaces-manifest` | Same, for `motion_capture_tracking_interfaces` |

Patches 2 and 3 are upstreamable; 1 is macOS/packaging-specific; 4 and 5 exist only because this
build uses pixi-build-ros.

## Limitations

**No positioning deck.** With only the AI deck fitted there is no position reference, so
`stabilizer.estimator` is set to `1` (complementary) — Kalman diverges without one, reading tens of
metres while stationary. `/cf1/pose` orientation is valid but **position is not**, and `takeoff`,
`land`, `go_to`, `cmd_position` and `cmd_hover` are unusable. Yaw drifts too, since the 2.1 has no
magnetometer. Fit a Flow deck v2, Lighthouse, Loco or mocap, then set `estimator: 2`.

**Camera intrinsics are a placeholder, not a calibration.** `fx`/`fy` are inherited from upstream's
324x324 values, `cx`/`cy` are the exact image centre, and distortion is assumed zero although the raw
image shows visible barrel distortion. Run `camera_calibration` at 324x244 before trusting
rectification or projection.

**The camera mount offset is an estimate.** `camera_translation` in `config/aideck_streamer.yaml` is
a guess for a top-mounted deck.

**IMU covariances are all zeros**, which `sensor_msgs/Imu` defines as "unknown". Fine for
visualization; an EKF needs real values, measured from ~60 s of stationary capture.

**`backend:=sim` does not work** — `crazyflie_sim` imports `cffirmware`, a separate SWIG build from
`bitcraze/crazyflie-firmware` that is not packaged here.
