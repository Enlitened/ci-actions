"""Name the devices standing between this runner and a usable simulator.

Reads `simctl list devices -j` on stdin and prints one `action\tudid\tname` line
per device the caller should act on. Like `resolve.py` it only reads and prints;
the shell does the acting, so what this decides can be checked without any
device being touched.

Two things are reclaimed, both of them left behind by a *previous* run rather
than created by this one:

  - **Leaked parallel-testing clones.** `xcodebuild -parallel-testing-enabled`
    creates "Clone N of <device>" and deletes them when it finishes. A run that
    is killed — a cancelled workflow, a stopped job, a crashed xcodebuild —
    never finishes, and its clones are left booted. They hold the runtime open
    and accumulate one set per interrupted run.

  - **A device left booted.** CoreSimulator will enumerate a booted device long
    after SpringBoard on it has stopped answering, which is the whole gap this
    covers: `await-simulator` waited for the device to be *listed* and then
    handed it to `xcodebuild`, which asked it to open an app and was refused
    with `Busy ("Application failed preflight checks")`. Nothing retries that —
    the job fails having executed no tests at all, and reports it as a test
    failure. Shutting the device down first costs nothing, because xcodebuild
    boots what it needs anyway.

Matching is exact, and on the *per-runner* name. Several runners share one Mac
and one CoreSimulator, each with its own `iPhone 17 Pro (<runner>)`, so a
substring test would let one runner shut down another runner's device in the
middle of its run — which is the failure this is supposed to prevent, caused by
the thing meant to prevent it.
"""

import json
import sys


def reclaimable(devices: dict, target: str):
    """Yield (action, udid, name) for every device that is in this runner's way."""
    for entries in devices.values():
        for device in entries:
            name = device.get("name", "")
            udid = device.get("udid")
            if not udid:
                continue
            if name.startswith("Clone ") and name.endswith(f" of {target}"):
                yield "delete", udid, name
            elif name == target and device.get("state") != "Shutdown":
                yield "shutdown", udid, name


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: reclaim.py <device name>", file=sys.stderr)
        return 2

    try:
        devices = json.load(sys.stdin)["devices"]
    except Exception:
        # No answer from CoreSimulator is not the same as nothing to reclaim, but
        # it is the same response: leave the devices alone and let the caller's
        # own waiting deal with it.
        return 0

    for action, udid, name in reclaimable(devices, sys.argv[1]):
        print(f"{action}\t{udid}\t{name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
