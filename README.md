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

> Real hardware: a Crazyflie 2.1 Brushless, a Crazyradio, and — for the camera — an AI-deck 1.1.

## Topics

| Topic | Type | Rate | |
|---|---|---|---|
| `/cf1/imu` | `sensor_msgs/Imu` | 50 Hz | Added by patch; upstream has no IMU topic |
| `/cf1/pose` | `geometry_msgs/PoseStamped` | 10 Hz | Orientation valid, **position is not** |
| `/cf1/status` | `crazyflie_interfaces/Status` | 1 Hz | |
| `/camera/image` | `sensor_msgs/Image` | ~8 Hz | 324x244 `mono8`, over WiFi not the radio |
| `/camera/camera_info` | `sensor_msgs/CameraInfo` | ~8 Hz | Placeholder intrinsics |
| `/tf`, `/tf_static` | `tf2_msgs/TFMessage` | | `world`→`cf1`, `cf1`→`cf1/camera` |

## Setup

```bash
pixi run setup     # clone crazyswarm2 + motion_capture_tracking at pinned SHAs, apply patches/
pixi install
```

## Usage

```bash
pixi run scan
pixi run server    # cflib backend; prefer it over server-cpp on Brushless,
                   # cflib tracks new hardware faster than crazyflie_cpp
pixi run camera    # requires joining the deck's AP first
pixi run viz       # rewire record --all
```

`scripts/arm_cycle.py` arms for a fixed duration then disarms. Brushless needs arming before the
motors spin; **it spins the props**.

## Development

`src/` is gitignored and reset by `pixi run setup`. **Never edit it directly** — change the patch:

```bash
git -C src/crazyswarm2 diff -- <paths> > patches/000N-<name>.patch
pixi clean --build && pixi install
```

`pixi install` on its own **silently skips rebuilding** edited source packages: it reports success,
produces no `.conda` artifact, and leaves the stale copy in `.pixi/envs/`. Always `pixi clean --build`
first and verify the change actually reached the env.

## Patches

| Patch | |
|---|---|
| `0001-macos-build-fixes` | crazyflie-link-cpp's `Findlibusb.cmake` demands a static `libusb-1.0.a` on macOS, which conda-forge does not ship. conda's Eigen3 exports only the imported target, not `EIGEN3_INCLUDE_DIRS`. `crazyflie_cpp` and `crazyflieLinkCpp` were built but never installed, so the binaries dangled once the build tree went away |
| `0002-imu-default-topic` | Adds `imu` as a fifth `default_topic`, both backends (plus docs + commented example). No orientation: a firmware log block holds 26 bytes and six `float32` uses 24, so the attitude estimate does not fit — hence `orientation_covariance[0] = -1` |
| `0003-aideck-streamer-fixes` | `reshape(width, height)` was transposed, and since 324×244 == 244×324 numpy accepted it silently and sheared the image. Bayer demosaic was applied to greyscale data. `image_height` said 324 where the HM01B0 is 244. Publishes `mono8` rather than inflating 4× to RGBA. Broadcasts the camera's static transform. Publishes on receive instead of from a second timer, which was dropping ~⅓ of frames |
| `0004`, `0005` | Per-package `pixi.toml` — upstream ships none |

## Gotchas

- **The GAP8 serves one TCP client.** Probing the port with `nc` first can leave the deck unwilling
  to serve the streamer. Let the node connect first.
- **macOS drifts back to a network with internet**, silently dropping the deck's AP. Check
  `ifconfig en0 | grep "inet "` for `192.168.4.x`.
- **`cflib` 0.1.32 caps `packaging<26`.** Without the pin the solve takes 26.x, silently downgrades
  cflib to 0.1.17, and fails at runtime with `'Crazyflie' object has no attribute 'fully_connected'`.

For AI-deck firmware flashing, follow [Bitcraze's guide](https://www.bitcraze.io/documentation/tutorials/getting-started-with-aideck/) — use the `_with_ap` binary so the deck broadcasts its own access point.

## Limitations

**No positioning deck**, so `stabilizer.estimator` is `1` (complementary) — Kalman diverges without a
position reference, reading tens of metres while stationary. Position in `/cf1/pose` is meaningless
and `takeoff`/`land`/`go_to`/`cmd_position`/`cmd_hover` are unusable. Yaw drifts; the 2.1 has no
magnetometer. Fit a Flow deck v2, Lighthouse, Loco or mocap, then set `estimator: 2`.

**Camera intrinsics are a placeholder, not a calibration** — `fx`/`fy` inherited from upstream's
324×324 values, `cx`/`cy` the image centre, distortion assumed zero despite visible barrel
distortion. The mount offset in `config/aideck_streamer.yaml` is likewise an estimate.

**IMU covariances are all zeros** — "unknown" per `sensor_msgs/Imu`. Fine for visualization, not for
an EKF.

**`backend:=sim` does not work** — `crazyflie_sim` imports `cffirmware`, a separate SWIG build that
is not packaged here.
