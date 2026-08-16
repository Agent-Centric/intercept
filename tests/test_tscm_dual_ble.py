"""TSCM dual BLE: host adapter + Ubertooth One."""

from datetime import datetime
from unittest.mock import MagicMock, patch

from utils.bluetooth.aggregator import DeviceAggregator
from utils.bluetooth.models import BTObservation
from utils.bluetooth.scanner import BluetoothScanner
from utils.bluetooth.ubertooth_scanner import UbertoothScanner


def test_ubertooth_hardware_present_detects_lsusb():
    fake = MagicMock()
    fake.stdout = "Bus 001 Device 004: ID 1d50:6002 OpenMoko, Inc. Ubertooth One\n"
    fake.returncode = 0
    with patch("subprocess.run", return_value=fake):
        assert UbertoothScanner.hardware_present() is True


def test_ubertooth_hardware_present_false_when_missing():
    fake = MagicMock()
    fake.stdout = "Bus 001 Device 003: ID 0bda:b85b Realtek Semiconductor Corp. Bluetooth Radio\n"
    fake.returncode = 0
    with patch("subprocess.run", return_value=fake):
        assert UbertoothScanner.hardware_present() is False


def test_aggregator_tracks_heard_by_radios():
    agg = DeviceAggregator()
    host = BTObservation(
        timestamp=datetime.now(),
        address="AA:BB:CC:DD:EE:FF",
        adapter_id="bleak",
    )
    uber = BTObservation(
        timestamp=datetime.now(),
        address="AA:BB:CC:DD:EE:FF",
        adapter_id="ubertooth",
    )
    device = agg.ingest(host)
    assert device.heard_by == ["bleak"]
    device = agg.ingest(uber)
    assert device.heard_by == ["bleak", "ubertooth"]


def test_tscm_mode_starts_host_and_tries_ubertooth():
    scanner = BluetoothScanner()
    with (
        patch.object(scanner, "_start_fallback", return_value=(True, "bleak")) as host,
        patch.object(scanner, "_start_ubertooth", return_value=(True, "ubertooth")) as uber,
    ):
        assert scanner.start_scan(mode="tscm", duration_s=None) is True
        host.assert_called_once()
        uber.assert_called_once()
        assert scanner._active_backend == "bleak+ubertooth"


def test_tscm_mode_still_starts_if_ubertooth_missing():
    scanner = BluetoothScanner()
    with (
        patch.object(scanner, "_start_fallback", return_value=(True, "bleak")),
        patch.object(scanner, "_start_ubertooth", return_value=(False, None)),
    ):
        assert scanner.start_scan(mode="tscm", duration_s=None) is True
        assert scanner._active_backend == "bleak"


def test_attach_ubertooth_appends_backend_name():
    scanner = BluetoothScanner()
    scanner._active_backend = "bleak"
    scanner._status.is_scanning = True
    with patch.object(scanner, "_start_ubertooth", return_value=(True, "ubertooth")):
        assert scanner.attach_ubertooth() is True
        assert scanner._active_backend == "bleak+ubertooth"


def test_tscm_snapshot_uses_tscm_mode():
    from routes.bluetooth_v2 import get_tscm_bluetooth_snapshot

    mock = MagicMock()
    mock.is_scanning = False
    mock.get_devices.return_value = []
    with patch("routes.bluetooth_v2.get_bluetooth_scanner", return_value=mock):
        with patch("routes.bluetooth_v2.time.sleep"):
            get_tscm_bluetooth_snapshot(duration=1)
    mock.start_scan.assert_called_once()
    assert mock.start_scan.call_args.kwargs.get("mode") == "tscm" or mock.start_scan.call_args[1].get("mode") == "tscm"
