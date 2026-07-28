#!/usr/bin/env python3
"""Grab one frame from an Image topic and write it to a file.

Decodes rgba8/mono8 with numpy directly, so cv_bridge is not required.

    pixi run python scripts/save_image.py --output /tmp/aideck.png
"""

import argparse

import cv2
import numpy as np
import rclpy
from sensor_msgs.msg import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--topic', default='/camera/image')
    parser.add_argument('--output', default='/tmp/aideck.png')
    parser.add_argument('--timeout', type=float, default=15.0)
    args = parser.parse_args()

    rclpy.init()
    node = rclpy.create_node('save_image')
    received = []

    def callback(msg):
        received.append(msg)

    node.create_subscription(Image, args.topic, callback, 10)

    deadline = node.get_clock().now().nanoseconds + int(args.timeout * 1e9)
    while not received and node.get_clock().now().nanoseconds < deadline:
        rclpy.spin_once(node, timeout_sec=0.1)

    if not received:
        node.get_logger().error(f'no message on {args.topic} within {args.timeout}s')
        rclpy.shutdown()
        return 1

    msg = received[0]
    channels = {'rgba8': 4, 'rgb8': 3, 'mono8': 1}.get(msg.encoding)
    if channels is None:
        node.get_logger().error(f'unhandled encoding {msg.encoding}')
        rclpy.shutdown()
        return 1

    array = np.frombuffer(msg.data, dtype=np.uint8).reshape(msg.height, msg.width, channels)
    if channels == 4:
        array = cv2.cvtColor(array, cv2.COLOR_RGBA2BGR)
    elif channels == 3:
        array = cv2.cvtColor(array, cv2.COLOR_RGB2BGR)

    cv2.imwrite(args.output, array)
    print(f'{msg.width}x{msg.height} {msg.encoding} step={msg.step} -> {args.output}')

    rclpy.shutdown()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
