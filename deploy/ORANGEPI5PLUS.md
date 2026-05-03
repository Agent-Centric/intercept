# INTERCEPT Deployment — Orange Pi 5 Plus (RK3588)

## Hardware

| Component     | Detail                                      |
|---------------|---------------------------------------------|
| Board         | Orange Pi 5 Plus (RK3588)                   |
| CPU           | 4× Cortex-A76 @ 2.256 GHz + 4× Cortex-A55 @ 1.8 GHz |
| RAM           | 8 GB LPDDR5                                 |
| Storage       | 256 GB eMMC                                 |
| OS            | Orange Pi OS 1.2.0 (Ubuntu 22.04 Jammy)     |
| SDR           | Nooelec SMArTee XTR v5ee (Elonics E4000 tuner) |
| GPS           | u-blox 7 USB (gpsd, 3D fix)                 |

### SDR Tuner Notes
The E4000 tuner covers ~52–1100 MHz. **ADS-B at 1090 MHz is not supported** (PLL fails to lock).
Supported INTERCEPT modes with this hardware:
- VDL2 (136 MHz) — primary aircraft mode
- ACARS, APRS, Pager/POCSAG (~130–170 MHz)
- 433 MHz sensors
- TSCM / spectrum scan
- Satellite (weather)

For ADS-B, a second RTL-SDR dongle with an R820T2 tuner is required (--device-index 1).

## System Configuration

### Security
Unprivileged BPF disabled to mitigate Spectre v2:
```
/etc/sysctl.d/99-disable-unprivileged-bpf.conf
  kernel.unprivileged_bpf_disabled=1
```

### Sudoers
Passwordless sudo scoped to systemctl and pkill for the orangepi user:
```
/etc/sudoers.d/orangepi-systemctl
  orangepi ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/pkill
```

## Service Architecture

Boot order:
```
network-online.target + gpsd.service
          |
    intercept.service          (gunicorn + gevent, port 5050)
          |
  vdl2-autostart.service       (oneshot: waits for ready, POSTs /vdl2/start)
          |
      dumpvdl2                  (decodes 5× North America VDL2 frequencies)
```

## Installation

### 1. Clone and install INTERCEPT
```bash
git clone https://github.com/[repo]/intercept.git ~/intercept
cd ~/intercept && ./setup.sh
```

### 2. Install Python WebSocket support
```bash
sudo ~/intercept/venv/bin/pip install flask-sock
```

### 3. Install systemd services
```bash
sudo cp deploy/systemd/intercept.service /etc/systemd/system/
sudo cp deploy/systemd/vdl2-autostart.service /etc/systemd/system/
cp deploy/intercept-vdl2-start.sh ~/intercept-vdl2-start.sh
chmod +x ~/intercept-vdl2-start.sh
sudo systemctl daemon-reload
sudo systemctl enable intercept.service vdl2-autostart.service
```

### 4. Start services
```bash
sudo systemctl start intercept.service
# vdl2-autostart triggers automatically after intercept is ready
```

## Access
- Web UI: http://<device-ip>:5050
- Default port: 5050
- Logs: /var/log/intercept.log

## Service Management
```bash
# Status
sudo systemctl status intercept.service vdl2-autostart.service

# Restart everything
sudo systemctl restart intercept.service

# View live logs
tail -f /var/log/intercept.log | grep -v GPS

# Check VDL2 stream
ps aux | grep dumpvdl2
nc localhost 30003 | head    # (ADS-B SBS — if dump1090 running)
```

## VDL2 Frequencies (North America)
| Frequency  | Description          |
|------------|----------------------|
| 136.975 MHz | Primary worldwide   |
| 136.100 MHz | North America       |
| 136.650 MHz | North America       |
| 136.700 MHz | North America       |
| 136.800 MHz | North America       |
