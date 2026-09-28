#!/usr/bin/env python3
import argparse
import json
import os
import stat
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import sample


STAT_IDLE = "cpu  100 0 0 900 0 0 0 0 0 0\ncpu0 50 0 0 450 0 0 0 0 0 0\n"
STAT_BUSY = "cpu  400 0 0 920 0 0 0 0 0 0\ncpu0 200 0 0 460 0 0 0 0 0 0\n"
MEMINFO = """MemTotal:        8000000 kB
MemFree:         1000000 kB
MemAvailable:    5000000 kB
Buffers:          200000 kB
Cached:          1000000 kB
"""
NET_DEV = """Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 999999      1    0    0    0     0          0         0  999999      1    0    0    0     0       0          0
  eth0: 1000        1    0    0    0     0          0         0  2000        1    0    0    0     0       0          0
"""
NET_DEV_LATER = """Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 999999      1    0    0    0     0          0         0  999999      1    0    0    0     0       0          0
  eth0: 1001000     1    0    0    0     0          0         0  2002000     1    0    0    0     0       0          0
"""
ROUTE = """Iface	Destination	Gateway 	Flags	RefCnt	Use	Metric	Mask		MTU	Window	IRTT
eth0	00000000	0100A8C0	0003	0	0	100	00000000	0	0	0
"""


class ParseTests(unittest.TestCase):
    def test_cpu_percent_from_delta(self):
        first = sample.parse_cpu(STAT_IDLE)
        second = sample.parse_cpu(STAT_BUSY)
        self.assertIsNotNone(first)
        self.assertIsNotNone(second)
        self.assertAlmostEqual(sample.cpu_percent(first, second), 93.75, places=2)

    def test_cpu_guest_time_is_not_counted_twice(self):
        counters = sample.parse_cpu("cpu  100 10 20 800 5 1 1 3 50 4\n")
        self.assertEqual(counters, (805, 940))

    def test_ram_uses_memavailable(self):
        self.assertAlmostEqual(sample.ram_percent(MEMINFO), 37.5, places=2)

    def test_ram_available_before_total(self):
        self.assertEqual(sample.ram_percent("MemAvailable: 25 kB\nMemTotal: 100 kB\n"), 75)

    def test_ram_fallback_without_available(self):
        self.assertEqual(sample.ram_percent("MemTotal: 100 kB\nMemFree: 10 kB\nBuffers: 5 kB\nCached: 15 kB\n"), 70)

    def test_ram_malformed_and_missing_total(self):
        self.assertEqual(sample.ram_percent("MemTotal: bad\nMemAvailable: 25 kB\n"), 0)
        self.assertEqual(sample.ram_percent("MemTotal: 100 kB\nMemAvailable: bad\nMemFree: 40 kB\n"), 60)

    def test_default_route_beats_loopback(self):
        net = sample.parse_net_dev(NET_DEV)
        ifaces = sample.select_interfaces(sample.parse_default_routes(ROUTE), net)
        self.assertEqual(ifaces, ["eth0"])
        self.assertEqual(sample.sum_bytes(net, ifaces), (1000, 2000))

    def test_inactive_default_route_is_ignored(self):
        route = ROUTE + "eth1\t00000000\t0100A8C0\t0000\t0\t0\t100\t00000000\n"
        self.assertEqual(sample.parse_default_routes(route), ["eth0"])

    def test_skip_loopback_when_no_route(self):
        net = sample.parse_net_dev(NET_DEV)
        ifaces = sample.select_interfaces([], iter(net))
        self.assertEqual(ifaces, ["eth0"])

    def test_ipv6_default_route_and_vpn_interface(self):
        route = "0" * 32 + " 00 " + "0" * 32 + " 00 " + "0" * 32 + " 00000001 00000000 00000000 00000003 wg0\n"
        self.assertEqual(sample.parse_ipv6_default_routes(route), ["wg0"])
        self.assertEqual(sample.select_interfaces(["wg0", "wg0"], ["lo", "wg0", "eth0"]), ["wg0"])

    def test_network_peak_tracks_and_decays(self):
        self.assertEqual(sample.network_peak(5_000_000, 1_000_000), 5_000_000)
        self.assertEqual(sample.network_peak(0, 5_000_000), 4_600_000)

    def test_filesystem_percent_excludes_reserved_blocks(self):
        stats = SimpleNamespace(f_blocks=1000, f_bfree=800, f_bavail=150)
        self.assertAlmostEqual(sample.filesystem_percent(statvfs=lambda _: stats), 200 * 100 / 350)

    def test_root_disk_operations_follow_mount_source(self):
        mountinfo = "731 420 0:29 /@ / rw - btrfs /dev/mapper/root rw\n"
        device = sample.root_block_device(
            mountinfo,
            device_stat=lambda path: SimpleNamespace(st_mode=stat.S_IFBLK, st_rdev=os.makedev(253, 0)),
        )
        self.assertEqual(device, (253, 0))
        self.assertEqual(sample.disk_operations("253 0 dm-0 10 0 50 2 20 0 60 3 0 0 0", device), (10, 20))

    def test_root_disk_falls_back_to_mount_device_number(self):
        mountinfo = "36 35 259:2 / / rw - ext4 /dev/root rw\n"

        def missing_device(path):
            raise FileNotFoundError(path)

        self.assertEqual(sample.root_block_device(mountinfo, device_stat=missing_device), (259, 2))

    def test_root_disk_decodes_mount_source(self):
        mountinfo = "36 35 259:2 / / rw - ext4 /dev/disk/by-label/my\\040disk rw\n"

        def device_stat(path):
            self.assertEqual(path, "/dev/disk/by-label/my disk")
            return SimpleNamespace(st_mode=stat.S_IFBLK, st_rdev=os.makedev(259, 2))

        self.assertEqual(sample.root_block_device(mountinfo, device_stat=device_stat), (259, 2))

    def test_sampler_two_ticks(self):
        files = {
            "/proc/stat": STAT_IDLE,
            "/proc/meminfo": MEMINFO,
            "/proc/net/dev": NET_DEV,
            "/proc/net/route": ROUTE,
            "/proc/diskstats": "253 0 dm-0 10 0 50 2 20 0 60 3 0 0 0",
        }
        clock = {"t": 0.0}

        def reader(path: str) -> str:
            return files.get(path, "")

        def now() -> float:
            return clock["t"]

        sampler = sample.Sampler(reader=reader, now=now)
        sampler.disk_device = (253, 0)
        first = sampler.snapshot()
        self.assertEqual(first["ram"], 37.5)
        self.assertEqual(first["cpu"], 0)

        files["/proc/stat"] = STAT_BUSY
        files["/proc/net/dev"] = NET_DEV_LATER
        files["/proc/diskstats"] = "253 0 dm-0 11 0 60 3 21 0 70 4 0 0 0"
        clock["t"] = 1.0
        second = sampler.snapshot()
        self.assertAlmostEqual(second["cpu"], 93.75, places=2)
        self.assertEqual(second["down"], 50.0)
        self.assertEqual(second["up"], 100.0)
        self.assertEqual(second["ram"], 37.5)
        self.assertEqual(second["diskPulse"], 1)

        files["/proc/diskstats"] = "253 0 dm-0 1 0 10 1 1 0 10 1 0 0 0"
        clock["t"] = 2.0
        self.assertEqual(sampler.snapshot()["diskPulse"], 1)

    def test_bad_interval_is_rejected(self):
        for raw in ("nan", "inf", "-1", "0", "1e308"):
            with self.assertRaises(argparse.ArgumentTypeError):
                sample.interval_seconds(raw)


class CacheTests(unittest.TestCase):
    def test_cache_expiry_and_live_counters(self):
        clock = [0.0]
        reads = []
        files = {"/proc/net/dev": NET_DEV, "/proc/net/route": ROUTE,
                 "/proc/stat": STAT_IDLE, "/proc/meminfo": MEMINFO}
        def reader(path):
            reads.append(path)
            return files.get(path, "")
        with patch.object(sample, "filesystem_percent", side_effect=[20, 30]) as fs:
            sampler = sample.Sampler(reader=reader, now=lambda: clock[0])
            self.assertEqual(sampler.snapshot()["disk"], 20)
            files["/proc/net/dev"] = NET_DEV_LATER
            files["/proc/stat"] = STAT_BUSY
            clock[0] = 1
            result = sampler.snapshot()
            self.assertGreater(result["cpu"], 0)
            self.assertGreater(result["down"], 0)
            self.assertEqual(reads.count("/proc/net/route"), 1)
            self.assertEqual(fs.call_count, 1)
            clock[0] = 5
            sampler.snapshot()
            self.assertEqual(reads.count("/proc/net/route"), 2)
            self.assertEqual(reads.count("/proc/net/ipv6_route"), 2)
            clock[0] = 30
            self.assertEqual(sampler.snapshot()["disk"], 30)
            self.assertEqual(fs.call_count, 2)

    def test_interface_change_refreshes_routes_and_resets_rate(self):
        clock = [0.0]
        files = {"/proc/net/dev": NET_DEV, "/proc/net/route": ROUTE}
        reads = []
        def reader(path):
            reads.append(path)
            return files.get(path, "")
        sampler = sample.Sampler(reader=reader, now=lambda: clock[0])
        sampler.snapshot()
        files["/proc/net/dev"] = NET_DEV_LATER.replace("eth0", "wg0")
        files["/proc/net/route"] = ROUTE.replace("eth0", "wg0")
        clock[0] = 1
        result = sampler.snapshot()
        self.assertEqual(reads.count("/proc/net/route"), 2)
        self.assertEqual(sampler.prev_ifaces, ["wg0"])
        self.assertEqual(result["down"], 0)
        self.assertEqual(result["up"], 0)


class ManifestTests(unittest.TestCase):
    def test_manifest_contract(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        with open(os.path.join(root, "manifest.json"), encoding="utf-8") as handle:
            manifest = json.load(handle)
        self.assertEqual(manifest["schemaVersion"], 1)
        self.assertEqual(manifest["id"], "troy.mini-omatop")
        self.assertEqual(manifest["kinds"], ["panel"])
        self.assertTrue(manifest["keepLoaded"])
        self.assertEqual(manifest["entryPoints"]["panel"], "Panel.qml")
        for name in ("Panel.qml", "MeterStrip.qml", "Sampler.qml", "sample.py"):
            self.assertTrue(os.path.isfile(os.path.join(root, name)), name)

class OnceTests(unittest.TestCase):
    def test_once_prints_json(self):
        import subprocess
        import sys

        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        completed = subprocess.run(
            [sys.executable, os.path.join(root, "sample.py"), "--once"],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        line = completed.stdout.strip().splitlines()[-1]
        payload = json.loads(line)
        for key in ("cpu", "ram", "down", "up", "disk"):
            self.assertIn(key, payload)
            self.assertGreaterEqual(payload[key], 0)
            self.assertLessEqual(payload[key], 100)


if __name__ == "__main__":
    unittest.main()
