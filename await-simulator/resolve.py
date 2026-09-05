"""Print a simulator's device type and runtime, or exit non-zero if it is absent.

Matching happens on `simctl`'s JSON rather than by grepping its text listing,
because a per-repository clone's name *contains* the stock name: a substring
test for "iPhone 17 Pro" also matches the line for "iPhone 17 Pro (japa)", and
would report a device as present that is not the one being asked for.

Exit 1 covers both "no such device" and "CoreSimulator did not answer", which
the caller treats the same way — wait, and ask again.
"""

import json
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: resolve.py <device name>", file=sys.stderr)
        return 2
    wanted = sys.argv[1]

    try:
        devices = json.load(sys.stdin)["devices"]
    except Exception:
        return 1

    for runtime, entries in devices.items():
        for device in entries:
            if device.get("name") == wanted:
                print(f"{device['deviceTypeIdentifier']}\t{runtime}")
                return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
