#!/usr/bin/env python3
"""Arm a Crazyflie for a fixed duration, then disarm.

The disarm runs in a finally block, so an error mid-cycle still disarms.

    ros2 launch crazyflie launch.py backend:=cflib ...   # in another shell
    python scripts/arm_cycle.py --namespace cf1 --duration 5
"""

import argparse
import time

import rclpy
from crazyflie_interfaces.srv import Arm


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--namespace', default='cf1')
    parser.add_argument('--duration', type=float, default=5.0)
    parser.add_argument('--timeout', type=float, default=30.0)
    args = parser.parse_args()

    rclpy.init()
    node = rclpy.create_node('arm_cycle')
    client = node.create_client(Arm, f'/{args.namespace}/arm')

    if not client.wait_for_service(timeout_sec=args.timeout):
        node.get_logger().error(f'/{args.namespace}/arm never appeared')
        return 1

    def send(value):
        request = Arm.Request()
        request.arm = value
        future = client.call_async(request)
        rclpy.spin_until_future_complete(node, future, timeout_sec=15.0)
        return future.done()

    armed_at = None
    try:
        acked = send(True)
        armed_at = time.time()
        print(f'ARM    ack={acked}')
        time.sleep(args.duration)
    finally:
        acked = send(False)
        elapsed = time.time() - armed_at if armed_at else float('nan')
        print(f'DISARM ack={acked}')
        print(f'armed for {elapsed:.2f}s')

    rclpy.shutdown()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
