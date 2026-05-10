#!/usr/bin/env python3
"""JJY FPGA time-sync daemon.

Periodically streams a 21-byte ASCII time-set frame
("T2026-04-13T12:00:00\\n") to a Tang Nano 9K running the JJY simulator.
The FPGA parser is described in docs/jjy-fpga-design-doc.md §9.5.

Send timing is anchored to the "30 seconds past the minute" mark so that
the trailing newline never lands close to a minute rollover. This avoids
making the receiver see a frame that was truncated by a minute step,
which interferes with the wall-clock receiver's plausibility check.

Usage:
    python3 tools/jjy_sync.py                 # auto-detect port, 5 min interval
    python3 tools/jjy_sync.py --port /dev/cu.usbserial-XXX
    python3 tools/jjy_sync.py --once          # send once and exit (for testing)
    python3 tools/jjy_sync.py --interval 60   # sync every minute
"""
from __future__ import annotations

import argparse
import datetime as dt
import logging
import re
import sys
import time
from typing import Optional

try:
    import serial
    from serial.tools import list_ports
    _SERIAL_OK = True
except ImportError:
    serial = None  # type: ignore
    list_ports = None  # type: ignore
    _SERIAL_OK = False


# Anchor offset within the minute. 30 s is far from any 60 s rollover.
ANCHOR_SECOND = 30


def detect_port(hint: Optional[str]) -> str:
    """Return a serial device path. Honours `hint` if provided.

    The Tang Nano 9K USB endpoint layout depends on revision:

    Older revisions use FTDI FT2232HQ (VID 0x0403, PID 0x6010) which is a
    dual-channel chip. macOS/Linux expose both channels as adjacent
    cu.usbserial-* devices. The two channels are split as:
      Channel A (lower trailing number, e.g. cu.usbserial-11400) -> JTAG
      Channel B (higher trailing number, e.g. cu.usbserial-11401) -> UART
    Sending bytes to channel A goes to the JTAG engine and never reaches
    the FPGA UART pin. The detector therefore prefers the higher-numbered
    sibling whenever a paired FTDI 0403:6010 device is found.

    Newer revisions (BL702/BL616) additionally expose a cu.debug-console
    endpoint that is purely a management channel (no FPGA UART wiring).
    The detector excludes it explicitly.
    """
    if hint:
        return hint
    ports = list(list_ports.comports())
    if not ports:
        raise RuntimeError("no serial ports found")

    rejects = ("debug-console", "debug_console", "debugconsole",
               "bluetooth")
    candidates = [p for p in ports
                  if not any(r in (p.device or "").lower() for r in rejects)]
    if not candidates:
        raise RuntimeError(
            "no usable serial ports found "
            "(only management-only channels like cu.debug-console were "
            "available; specify --port explicitly or use --list)")

    # FTDI dual-channel: pick the higher-numbered sibling (channel B = UART).
    ftdi = [p for p in candidates if p.vid == 0x0403 and p.pid == 0x6010]
    if len(ftdi) >= 2:
        def trailing_int(p):
            m = re.search(r"(\d+)$", p.device or "")
            return int(m.group(1)) if m else -1
        ftdi.sort(key=trailing_int, reverse=True)
        return ftdi[0].device
    if len(ftdi) == 1:
        return ftdi[0].device

    preferred = ("usbserial", "usbmodem", "ft2ch", "ftdi", "bl702", "bl616",
                 "usb-serial", "cdc")
    scored = []
    for idx, p in enumerate(candidates):
        text = " ".join(filter(None, (p.device, p.description,
                                      p.manufacturer, p.product))).lower()
        score = next((i for i, k in enumerate(preferred) if k in text), len(preferred))
        scored.append((score, idx, p.device))
    scored.sort()
    return scored[0][2]


def list_serial_ports() -> int:
    """Print all visible serial ports with their metadata."""
    ports = list(list_ports.comports())
    if not ports:
        print("(no serial ports found)")
        return 1
    rejects = ("debug-console", "debug_console", "debugconsole",
               "bluetooth")
    ftdi = [p for p in ports
            if p.vid == 0x0403 and p.pid == 0x6010
            and not any(r in (p.device or "").lower() for r in rejects)]
    chosen_b = None
    if len(ftdi) >= 2:
        def trailing_int(p):
            m = re.search(r"(\d+)$", p.device or "")
            return int(m.group(1)) if m else -1
        chosen_b = max(ftdi, key=trailing_int).device

    for p in ports:
        dev_lc = (p.device or "").lower()
        if any(r in dev_lc for r in rejects):
            flag = "  (rejected: management/non-UART channel)"
        elif p.device == chosen_b:
            flag = "  (preferred: FTDI Channel B = UART)"
        elif p.vid == 0x0403 and p.pid == 0x6010 and chosen_b is not None:
            flag = "  (skipped: FTDI Channel A = JTAG)"
        else:
            flag = ""
        print(f"device      : {p.device}{flag}")
        print(f"  description : {p.description}")
        print(f"  manufacturer: {p.manufacturer}")
        print(f"  product     : {p.product}")
        print(f"  vid/pid     : "
              f"{f'{p.vid:04x}' if p.vid else '----'}:"
              f"{f'{p.pid:04x}' if p.pid else '----'}")
        print(f"  serial #    : {p.serial_number}")
        print()
    return 0


def next_anchor(now: dt.datetime) -> dt.datetime:
    """Next instant whose second equals ANCHOR_SECOND, strictly after `now`."""
    candidate = now.replace(second=ANCHOR_SECOND, microsecond=0)
    if candidate <= now:
        candidate += dt.timedelta(minutes=1)
    return candidate


def sleep_until(target: dt.datetime) -> None:
    """Sleep coarse, then busy-wait the last ~20 ms for sub-ms accuracy."""
    while True:
        delta = (target - dt.datetime.now()).total_seconds()
        if delta <= 0.020:
            break
        time.sleep(min(delta - 0.020, 1.0))
    while dt.datetime.now() < target:
        pass


def make_frame(target: dt.datetime) -> bytes:
    return target.strftime("T%Y-%m-%dT%H:%M:%S\n").encode("ascii")


def send_at_anchor(ser: serial.Serial, log: logging.Logger,
                   delay_minutes: int) -> None:
    """Schedule a send so that the trailing '\\n' arrives at the next anchor.

    `delay_minutes` shifts the target forward by N minutes from "next anchor",
    used to space periodic sends at user-specified intervals.
    """
    target = next_anchor(dt.datetime.now())
    if delay_minutes > 0:
        target = target + dt.timedelta(minutes=delay_minutes)
    sleep_until(target)
    payload = make_frame(target)
    ser.write(payload)
    ser.flush()
    log.info("sent %s", payload.decode("ascii").strip())


def setup_logging(verbose: bool) -> logging.Logger:
    log = logging.getLogger("jjy_sync")
    log.setLevel(logging.DEBUG if verbose else logging.INFO)
    if not log.handlers:
        h = logging.StreamHandler()
        h.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))
        log.addHandler(h)
    return log


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--port", help="serial device path (auto-detect if omitted)")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--interval", type=int, default=300,
                   help="seconds between sends (default 300 = 5 min)")
    p.add_argument("--retry", type=int, default=10,
                   help="seconds to wait before retrying on errors")
    p.add_argument("--once", action="store_true",
                   help="send a single frame at the next anchor and exit")
    p.add_argument("--list", action="store_true",
                   help="enumerate available serial ports and exit")
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args()

    log = setup_logging(args.verbose)

    if not _SERIAL_OK:
        log.error("pyserial is required. Install with: pip install -r tools/requirements.txt")
        return 1

    if args.list:
        return list_serial_ports()

    if args.interval < 60:
        log.warning("interval < 60 s collapses to per-minute sends "
                    "(anchor is fixed at the %d-second mark)", ANCHOR_SECOND)
    delay_minutes = max(1, args.interval // 60)

    while True:
        try:
            port = detect_port(args.port)
        except RuntimeError as e:
            log.error("%s; retrying in %ds", e, args.retry)
            time.sleep(args.retry)
            continue

        log.info("opening %s @ %d bps", port, args.baud)
        try:
            with serial.Serial(port, args.baud, timeout=1) as ser:
                if args.once:
                    send_at_anchor(ser, log, delay_minutes=0)
                    return 0
                while True:
                    send_at_anchor(ser, log, delay_minutes)
        except (serial.SerialException, OSError) as e:
            log.warning("serial error: %s; retrying in %ds", e, args.retry)
            time.sleep(args.retry)
        except KeyboardInterrupt:
            log.info("interrupted")
            return 0


if __name__ == "__main__":
    sys.exit(main())
