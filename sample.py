#!/usr/bin/env python3
"""Sample CPU, RAM, network, and root filesystem usage as 0–100 percentages.

Prints one JSON object per line. CPU and network are rate-based, so the
first line is emitted after two counter snapshots.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import stat
import sys
import time
from typing import Callable, Iterable


def read_text(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return ""


def parse_cpu(stat_text: str) -> tuple[int, int] | None:
    fields = stat_text.partition("\n")[0].split()
    if len(fields) < 5 or fields[0] != "cpu":
        return None
    try:
        values = [int(part) for part in fields[1:]]
    except ValueError:
        return None
    # guest fields are already included in user and nice.
    total = sum(values[:8])
    idle = values[3] + (values[4] if len(values) > 4 else 0)
    return idle, total


def cpu_percent(previous: tuple[int, int], current: tuple[int, int]) -> float:
    prev_idle, prev_total = previous
    idle, total = current
    total_delta = total - prev_total
    if total_delta <= 0:
        return 0.0
    idle_delta = idle - prev_idle
    busy = 1.0 - (idle_delta / total_delta)
    return max(0.0, min(100.0, busy * 100.0))


def ram_percent(meminfo_text: str) -> float:
    total = 0
    available = None
    free = buffers = cached = 0
    for line in meminfo_text.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        key, raw = parts[0], parts[1]
        if key not in ("MemTotal:", "MemAvailable:", "MemFree:", "Buffers:", "Cached:"):
            continue
        try:
            value = int(raw)
        except ValueError:
            continue
        if key == "MemTotal:":
            total = value
        elif key == "MemAvailable:":
            available = value
        elif key == "MemFree:":
            free = value
        elif key == "Buffers:":
            buffers = value
        elif key == "Cached:":
            cached = value
        if total > 0 and available is not None:
            break
    if total <= 0:
        return 0.0
    if available is None:
        available = free + buffers + cached
    used = max(0, total - available)
    return max(0.0, min(100.0, used * 100.0 / total))


def parse_net_dev(text: str) -> dict[str, tuple[int, int]]:
    out: dict[str, tuple[int, int]] = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        name, rest = line.split(":", 1)
        name = name.strip()
        fields = rest.split()
        if len(fields) < 9:
            continue
        try:
            out[name] = (int(fields[0]), int(fields[8]))
        except ValueError:
            continue
    return out


def parse_default_routes(route_text: str) -> list[str]:
    found: list[str] = []
    for line in route_text.splitlines():
        fields = line.split()
        if len(fields) < 4 or fields[1] != "00000000":
            continue
        try:
            active = int(fields[3], 16) & 1
        except ValueError:
            continue
        if active and fields[0] not in found:
            found.append(fields[0])
    return found


def parse_ipv6_default_routes(route_text: str) -> list[str]:
    found: list[str] = []
    for line in route_text.splitlines():
        fields = line.split()
        if len(fields) >= 10 and fields[0] == "0" * 32 and fields[1] == "00":
            name = fields[-1]
            if name not in found:
                found.append(name)
    return found


def select_interfaces(route_ifaces: Iterable[str], all_ifaces: Iterable[str]) -> list[str]:
    names = list(all_ifaces)
    available = set(names)
    routed = list(dict.fromkeys(name for name in route_ifaces if name in available and name != "lo"))
    if routed:
        return routed
    return [name for name in names if name != "lo"]


def sum_bytes(net: dict[str, tuple[int, int]], ifaces: Iterable[str]) -> tuple[int, int]:
    rx = tx = 0
    for name in ifaces:
        entry = net.get(name)
        if not entry:
            continue
        rx += entry[0]
        tx += entry[1]
    return rx, tx


def network_peak(rate_bps: float, previous: float, floor_bps: float = 1_000_000.0) -> float:
    return max(previous * 0.92, rate_bps, floor_bps)


def filesystem_percent(path: str = "/", statvfs=os.statvfs) -> float:
    try:
        stats = statvfs(path)
    except OSError:
        return 0.0
    used = max(0, stats.f_blocks - stats.f_bfree)
    available = max(0, stats.f_bavail)
    capacity = used + available
    if capacity <= 0:
        return 0.0
    return max(0.0, min(100.0, used * 100.0 / capacity))


def root_block_device(mountinfo: str, device_stat=os.stat) -> tuple[int, int] | None:
    for line in mountinfo.splitlines():
        before, separator, after = line.partition(" - ")
        fields = before.split()
        source = after.split()
        if not separator or len(fields) < 5 or fields[4] != "/" or len(source) < 2:
            continue
        path = source[1]
        for escaped, character in (("\\040", " "), ("\\011", "\t"), ("\\012", "\n"), ("\\134", "\\")):
            path = path.replace(escaped, character)
        if path.startswith("/"):
            try:
                device = device_stat(path)
            except OSError:
                pass
            else:
                if stat.S_ISBLK(device.st_mode):
                    return os.major(device.st_rdev), os.minor(device.st_rdev)
        try:
            major, minor = fields[2].split(":", 1)
            return int(major), int(minor)
        except ValueError:
            return None
    return None


def disk_operations(diskstats: str, device: tuple[int, int] | None) -> tuple[int, int] | None:
    if device is None:
        return None
    for line in diskstats.splitlines():
        fields = line.split()
        if len(fields) < 8:
            continue
        try:
            if (int(fields[0]), int(fields[1])) == device:
                return int(fields[3]), int(fields[7])
        except ValueError:
            continue
    return None


class Sampler:
    def __init__(self, reader: Callable[[str], str] | None = None, now: Callable[[], float] | None = None):
        self.reader = reader or read_text
        self.now = now or time.monotonic
        self.prev_cpu: tuple[int, int] | None = None
        self.prev_rx = -1
        self.prev_tx = -1
        self.prev_ifaces: list[str] = []
        self.prev_stamp = 0.0
        self.net_peak = 1_000_000.0
        self.disk_device = root_block_device(self.reader("/proc/self/mountinfo"))
        self.next_disk_probe = 0.0
        self.prev_disk_operations: tuple[int, int] | None = None
        self.disk_pulse = 0
        self.next_route_probe = 0.0
        self.route_ifaces: list[str] = []
        self.known_interfaces: set[str] | None = None
        self.next_filesystem_probe = 0.0
        self.filesystem_usage = 0.0

    def snapshot(self) -> dict[str, float | int]:
        stamp = self.now()
        cpu = parse_cpu(self.reader("/proc/stat"))
        ram = ram_percent(self.reader("/proc/meminfo"))
        net = parse_net_dev(self.reader("/proc/net/dev"))
        interfaces = set(net)
        if stamp >= self.next_route_probe or interfaces != self.known_interfaces:
            self.route_ifaces = parse_default_routes(self.reader("/proc/net/route"))
            self.route_ifaces += parse_ipv6_default_routes(self.reader("/proc/net/ipv6_route"))
            self.next_route_probe = stamp + 5
            self.known_interfaces = interfaces
        ifaces = select_interfaces(self.route_ifaces, net.keys())
        if stamp >= self.next_filesystem_probe:
            self.filesystem_usage = filesystem_percent()
            self.next_filesystem_probe = stamp + 30
        rx, tx = sum_bytes(net, ifaces)
        diskstats = self.reader("/proc/diskstats")
        disk_ops = disk_operations(diskstats, self.disk_device)
        if disk_ops is None and stamp >= self.next_disk_probe:
            self.next_disk_probe = stamp + 30
            device = root_block_device(self.reader("/proc/self/mountinfo"))
            if device != self.disk_device:
                self.disk_device = device
                self.prev_disk_operations = None
                disk_ops = disk_operations(diskstats, device)
        if disk_ops is not None:
            if self.prev_disk_operations is not None and all(
                current >= previous for current, previous in zip(disk_ops, self.prev_disk_operations)
            ) and disk_ops != self.prev_disk_operations:
                self.disk_pulse += 1
            self.prev_disk_operations = disk_ops

        cpu_pct = 0.0
        if cpu and self.prev_cpu:
            cpu_pct = cpu_percent(self.prev_cpu, cpu)
        if cpu:
            self.prev_cpu = cpu

        down_pct = up_pct = 0.0
        elapsed = (stamp - self.prev_stamp) if self.prev_rx >= 0 else 0.0
        same = ifaces == self.prev_ifaces
        if self.prev_rx >= 0 and elapsed > 0 and same and rx >= self.prev_rx and tx >= self.prev_tx:
            down_rate = (rx - self.prev_rx) / elapsed
            up_rate = (tx - self.prev_tx) / elapsed
            self.net_peak = network_peak(max(down_rate, up_rate), self.net_peak)
            down_pct = min(100.0, down_rate * 100.0 / self.net_peak)
            up_pct = min(100.0, up_rate * 100.0 / self.net_peak)

        self.prev_rx, self.prev_tx = rx, tx
        self.prev_ifaces = list(ifaces)
        self.prev_stamp = stamp

        return {
            "cpu": round(cpu_pct, 2),
            "ram": round(ram, 2),
            "down": round(down_pct, 2),
            "up": round(up_pct, 2),
            "disk": round(self.filesystem_usage, 2),
            "diskPulse": self.disk_pulse,
        }


def emit(sample: dict[str, float | int]) -> None:
    sys.stdout.write(json.dumps(sample, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def run(interval: float) -> None:
    sampler = Sampler()
    sampler.snapshot()
    time.sleep(min(0.25, interval / 4))
    emit(sampler.snapshot())
    while True:
        time.sleep(interval)
        emit(sampler.snapshot())


def interval_seconds(raw: str) -> float:
    try:
        value = float(raw)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("interval must be between 0.25 and 3600 seconds") from exc
    if not math.isfinite(value) or not 0.25 <= value <= 3600:
        raise argparse.ArgumentTypeError("interval must be between 0.25 and 3600 seconds")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description="Emit mini-omatop JSON samples.")
    parser.add_argument("--interval", type=interval_seconds, default=1.0, help="Seconds between samples (at least 0.25).")
    parser.add_argument("--once", action="store_true", help="Print one sample and exit.")
    args = parser.parse_args()
    if args.once:
        sampler = Sampler()
        sampler.snapshot()
        time.sleep(0.15)
        emit(sampler.snapshot())
        return 0
    try:
        run(args.interval)
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        os._exit(0)
