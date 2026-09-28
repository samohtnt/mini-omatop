"""Synthetic Linux configurations; these do not emulate physical hardware."""

import json
import math
import os
import stat
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import sample


def missing_device(path):
    raise FileNotFoundError(path)


def ipv4_route(name, flags="0003", mask="00000000"):
    return f"{name} 00000000 0100000A {flags} 0 0 100 {mask} 0 0 0\n"


def ipv6_route(name, flags="00000003", prefix="00"):
    return f"{'0' * 32} {prefix} {'0' * 32} 00 {'0' * 32} 00000064 0 0 {flags} {name}\n"


def network_counters(name, rx, tx):
    return f"{name}: {rx} 0 0 0 0 0 0 0 {tx} 0 0 0 0 0 0 0\n"


class CpuCompatibilityTests(unittest.TestCase):
    def test_small_to_server_cpu_counts_with_large_counters(self):
        base = 2**54
        for count in (1, 2, 4, 8, 12, 16, 24, 32, 64, 96, 128, 256, 512):
            with self.subTest(logical_cpus=count):
                # Noncontiguous IDs also exercise disabled cores and CPU hotplug.
                previous = {i * 2: (base, base * 2) for i in range(count)}
                current = {i * 2: (base + 75, base * 2 + 100) for i in range(count)}
                readings = sample.logical_cpu_samples(previous, current)
                self.assertEqual([entry["id"] for entry in readings], list(previous))
                self.assertTrue(all(entry["usage"] == 25 for entry in readings))

    def test_guest_and_steal_time(self):
        # Guest is already in user/nice. Steal counts as non-idle capacity.
        first = sample.parse_cpu("cpu 100 0 0 100 0 0 0 0 40 0")
        second = sample.parse_cpu("cpu 140 0 0 140 0 0 0 20 60 0")
        self.assertAlmostEqual(sample.cpu_percent(first, second), 60)

    def test_iowait_counter_decrease_never_emits_invalid_usage(self):
        readings = sample.logical_cpu_samples({0: (100, 200)}, {0: (99, 250)})
        self.assertEqual(readings, [{"id": 0, "usage": None}])


class StorageCompatibilityTests(unittest.TestCase):
    def test_root_block_device_matrix(self):
        devices = [
            ("sata-ext4", "ext4", "/dev/sda2", (8, 2)),
            ("nvme-xfs", "xfs", "/dev/nvme0n1p2", (259, 2)),
            ("emmc-ext4", "ext4", "/dev/mmcblk0p2", (179, 2)),
            ("virtio-ext4", "ext4", "/dev/vda2", (252, 2)),
            ("luks-lvm-btrfs", "btrfs", "/dev/mapper/root", (253, 0)),
            ("mdraid-xfs", "xfs", "/dev/md0", (9, 0)),
        ]
        for label, filesystem, source, numbers in devices:
            with self.subTest(configuration=label):
                mountinfo = f"1 0 0:29 /@ / rw - {filesystem} {source} rw\n"
                device = SimpleNamespace(st_mode=stat.S_IFBLK, st_rdev=os.makedev(*numbers))
                resolved = sample.root_block_device(mountinfo, device_stat=lambda _: device)
                self.assertEqual(resolved, numbers)
                major, minor = numbers
                counters = f"{major} {minor} arbitrary-name 10 0 50 2 20 0 60 3 0 0 0\n"
                self.assertEqual(sample.disk_operations(counters, resolved), (10, 20))

    def test_non_block_roots_keep_capacity_without_activity(self):
        for filesystem, source in (("nfs", "server:/root"), ("overlay", "overlay"),
                                   ("tmpfs", "tmpfs"), ("zfs", "tank/root")):
            with self.subTest(filesystem=filesystem):
                files = {
                    "/proc/self/mountinfo": f"1 0 0:99 / / rw - {filesystem} {source} rw\n",
                    "/proc/diskstats": "8 0 sda 10 0 50 2 20 0 60 3 0 0 0\n",
                }
                with patch.object(sample, "filesystem_percent", return_value=42):
                    sampler = sample.Sampler(reader=lambda path: files.get(path, ""))
                    sampler.snapshot()
                    result = sampler.snapshot()
                self.assertEqual(result["disk"], 42)
                self.assertEqual(result["diskPulse"], 0)

    def test_missing_device_node_uses_mount_numbers(self):
        mountinfo = "1 0 259:2 / / rw - ext4 /dev/root rw\n"
        self.assertEqual(sample.root_block_device(mountinfo, missing_device), (259, 2))

    def test_capacity_extremes(self):
        for total, free, available, expected in (
            (100, 100, 100, 0), (100, 0, 0, 100), (100, 20, 0, 100),
            (0, 0, 0, 0), (2**54, 2**53, 2**53, 50),
        ):
            with self.subTest(blocks=(total, free, available)):
                stats = SimpleNamespace(f_blocks=total, f_bfree=free, f_bavail=available)
                self.assertEqual(sample.filesystem_percent(statvfs=lambda _: stats), expected)
        self.assertEqual(sample.filesystem_percent(statvfs=missing_device), 0)


class NetworkCompatibilityTests(unittest.TestCase):
    def test_ipv4_requires_active_default_not_rejected_route(self):
        routes = ipv4_route("wifi") + ipv4_route("down", flags="0000")
        routes += ipv4_route("reject", flags="0201")
        routes += ipv4_route("half-internet", mask="00000080")
        self.assertEqual(sample.parse_default_routes(routes), ["wifi"])

    def test_ipv6_requires_active_default_not_rejected_route(self):
        routes = ipv6_route("wifi") + ipv6_route("down", flags="00000000")
        routes += ipv6_route("reject", flags="00200201")
        routes += ipv6_route("bad", flags="invalid") + ipv6_route("subnet", prefix="40")
        self.assertEqual(sample.parse_ipv6_default_routes(routes), ["wifi"])

    def test_dual_stack_deduplicates_and_ignores_loopback(self):
        routes = sample.parse_default_routes(ipv4_route("wlan0"))
        routes += sample.parse_ipv6_default_routes(ipv6_route("wlan0"))
        self.assertEqual(sample.select_interfaces(routes, ["lo", "wlan0", "docker0"]), ["wlan0"])
        self.assertEqual(sample.select_interfaces([], ["lo"]), [])

    def test_interface_switch_counter_reset_and_zero_elapsed(self):
        clock = [0.0]
        files = {"/proc/net/dev": network_counters("eth0", 0, 0),
                 "/proc/net/route": ipv4_route("eth0")}
        sampler = sample.Sampler(reader=lambda path: files.get(path, ""), now=lambda: clock[0])
        sampler.snapshot()
        clock[0] = 1
        files["/proc/net/dev"] = network_counters("eth0", 1_000_000, 0)
        self.assertEqual(sampler.snapshot()["down"], 100)
        self.assertEqual(sampler.snapshot()["down"], 0)
        clock[0] = 2
        files["/proc/net/dev"] = network_counters("eth0", 10, 0)
        self.assertEqual(sampler.snapshot()["down"], 0)
        clock[0] = 3
        files["/proc/net/dev"] = network_counters("wg0", 9_000_000, 0)
        files["/proc/net/route"] = ipv4_route("wg0")
        self.assertEqual(sampler.snapshot()["down"], 0)
        self.assertEqual(sampler.prev_ifaces, ["wg0"])


class MissingDataTests(unittest.TestCase):
    def test_ram_sizes(self):
        for total in (256 * 1024, 16 * 1024**2, 1024**3):
            with self.subTest(kib=total):
                self.assertEqual(sample.ram_percent(
                    f"MemTotal: {total} kB\nMemAvailable: {total // 4} kB\n"), 75)

    def test_missing_and_malformed_proc_data_stays_finite(self):
        for raw in ("", "unavailable", "cpu x y z w\n"):
            with self.subTest(data=raw):
                sampler = sample.Sampler(reader=lambda _: raw)
                sampler.snapshot()
                result = sampler.snapshot()
                json.dumps(result, allow_nan=False)
                for key in ("cpu", "ram", "down", "up", "disk"):
                    self.assertTrue(math.isfinite(result[key]))
                    self.assertTrue(0 <= result[key] <= 100)


if __name__ == "__main__":
    unittest.main()
