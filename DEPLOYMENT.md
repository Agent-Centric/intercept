# INTERCEPT — Orange Pi 5 Plus Deployment

**Host:** `orangepi5plus` · `192.168.8.138:5050`
**Platform:** Orange Pi OS Jammy · Linux 6.1.43-rk3588 · ARM64
**INTERCEPT:** v2.26.13
**Deployed:** 2026-05-06

---

## Quick Start

```bash
# Access the web interface
http://192.168.8.138:5050

# SSH access
ssh orangepi@192.168.8.138

# Check service status
systemctl status intercept.service vdl2-autostart.service gpsd.service

# Manually restart SDR services if needed
curl -X POST http://localhost:5050/adsb/start \
  -H 'Content-Type: application/json' \
  -d '{"device":"0","gain":"40","sdr_type":"rtlsdr"}'

curl -X POST http://localhost:5050/acars/start \
  -H 'Content-Type: application/json' \
  -d '{"device":"1","gain":"40","sdr_type":"rtlsdr","frequencies":["131.550","131.725","131.825","130.025"]}'

curl -X POST http://localhost:5050/gps/auto-connect
```

---

## Hardware

| Index | Device | Tuner | Serial | Role |
|-------|--------|-------|--------|------|
| RTL-SDR 0 | Realtek RTL2838UHIDIR | R820T (24–1766 MHz) | `00000001` | ADS-B @ 1090 MHz |
| RTL-SDR 1 | Nooelec SMArTee XTR v5ee | E4000 (54 MHz–1.1 GHz) | `97064198` | ACARS @ 130–132 MHz |
| HackRF Pro | Great Scott Gadgets r1.2 | 1 MHz–6 GHz | `977c64de...` | Scanner / APRS / ADS-B |
| GPS | u-blox 7 (`/dev/ttyACM0`) | — | — | Position / time |

> **Important:** RTL-SDR device index assignment must not be swapped.
> The E4000 tuner (Nooelec) cannot tune to 1090 MHz due to a PLL gap — ADS-B must always use device 0 (Realtek R820T).

---

## Active Modes

| Mode | Decoder | Device | Frequencies |
|------|---------|--------|-------------|
| ADS-B | dump1090 | 0 — Realtek R820T | 1090 MHz |
| ACARS | acarsdec v3.7 | 1 — Nooelec E4000 | 130.025 / 131.550 / 131.725 / 131.825 MHz |
| GPS | gpsd | `/dev/ttyACM0` | — |

> ACARS is limited to 4 frequencies. The E4000 has a max bandwidth span of ~2.4 MHz.
> 129.125 MHz was excluded as it falls outside this range when combined with 131.825 MHz.

---

## Installed Tools

| Tool | Version | Path | Purpose |
|------|---------|------|---------|
| dump1090 | — | `/usr/local/sbin/dump1090` | ADS-B (RTL-SDR) |
| readsb | v3.16.14 | `/usr/local/bin/readsb` | ADS-B (SoapySDR/HackRF) |
| acarsdec | v3.7 | `/usr/local/bin/acarsdec` | ACARS decoder |
| dumpvdl2 | v2.6.0 | `/usr/local/bin/dumpvdl2` | VDL2 (RTL-SDR only) |
| LimeUtil | v20.10.0 | `/usr/bin/LimeUtil` | LimeSDR utilities |
| SoapyLMS7 | v20.10.0 | system | SoapySDR LimeSDR plugin |
| rx_fm | latest | `/usr/local/bin/rx_fm` | SoapySDR FM receiver |
| hackrf_info | v2026.01.3 | `/usr/local/bin/hackrf_info` | HackRF diagnostics |
| hackrf_sweep | v2026.01.3 | `/usr/local/bin/hackrf_sweep` | Wideband spectrum sweep |
| SoapySDR factories | — | — | `hackrf`, `lime` |

---

## Boot Sequence

Services start automatically in this order:

```
1. gpsd.service          → Opens /dev/ttyACM0
2. intercept.service     → Starts gunicorn on 0.0.0.0:5050
3. vdl2-autostart.service → Runs /home/orangepi/intercept-vdl2-start.sh
   ├── Waits for INTERCEPT to be ready
   ├── Allows session restore (20s)
   ├── Stops any conflicting SDR modes
   ├── Waits for devices to be free
   ├── Starts ADS-B on device 0 (Realtek)
   ├── Starts ACARS on device 1 (Nooelec)
   └── Auto-connects GPS (/dev/ttyACM0 if present)
```

**Autostart script:** `/home/orangepi/intercept-vdl2-start.sh`

---

## HackRF Configuration

The HackRF Pro uses v2026.01.3 firmware (API:1.10), flashed during deployment.

When connected, it enables:
- **Scanner / Listening Post** — via `rx_fm` (any frequency, wideband)
- **APRS** — 144.390 MHz via `rx_fm`
- **ADS-B** — via `readsb` with `sdr_type: "hackrf"` (requires free device)
- **SubGHz** — TX/RX 300–928 MHz ISM bands
- **TSCM sweeps** — via `hackrf_sweep`

To start ADS-B on HackRF (when RTL-SDRs are unavailable):
```bash
curl -X POST http://localhost:5050/adsb/start \
  -H 'Content-Type: application/json' \
  -d '{"device":"0","gain":"40","sdr_type":"hackrf"}'
```

To reflash firmware in future:
```bash
hackrf_spiflash -w hackrf_pro_usb.bin
# Unplug and replug HackRF after flashing
```

---

## GPS Setup

```
Device:   u-blox 7 (USB ID 1546:01a7)
Port:     /dev/ttyACM0 (USB-C port)
Daemon:   gpsd
Config:   /etc/default/gpsd → DEVICES="/dev/ttyACM0"
Endpoint: gpsd://localhost:2947
```

GPS requires a clear sky view to acquire a fix. The unit initialises correctly
on boot but will report `lat=0.0 lon=0.0` until satellites are acquired.

---

## Troubleshooting

**Services stopped after reboot**
INTERCEPT's session restore briefly claims SDR devices, sometimes racing the
autostart script. Wait ~60 seconds or restart via the web UI or API.

**ADS-B not starting — device busy**
```bash
sudo pkill -f dump1090
curl -X POST http://localhost:5050/adsb/start \
  -H 'Content-Type: application/json' \
  -d '{"device":"0","gain":"40","sdr_type":"rtlsdr"}'
```

**ACARS frequencies too far apart error**
Only use frequencies within a ~2 MHz span. The current set
(130.025–131.825 MHz = 1.8 MHz span) is within the E4000 limit.

**HackRF permission denied**
```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```

**GPS no fix**
Place the u-blox near a window or outdoors. 4+ satellites with SNR > 20 dB
are needed for a 3D fix.

---

## System Specs

| | |
|-|-|
| Board | Orange Pi 5 Plus |
| SoC | Rockchip RK3588 |
| RAM | 8 GB |
| Storage | 256 GB eMMC |
| OS | Ubuntu Jammy 22.04 (Orange Pi 1.2.0) |
| Kernel | Linux 6.1.43-rockchip-rk3588 |
| IP | 192.168.8.138 |
