#!/usr/bin/env python3
"""Read the Legion Go 1 (83E1) fan RPM from the embedded controller.

Register 0xC664, 16-bit little endian, through /dev/port ports 0x4E/0x4F
with the 0x11 / 0x10 / 0x12 command sequence (same path the LeGo1 Fan
Control plugin uses). yogafan.ko does not expose fan1_input on this
firmware, so the EC is the only reliable RPM source.

Run as root:  sudo python3 rpm_ec.py
"""
import os
import sys

try:
    fd = os.open("/dev/port", os.O_RDWR)
except PermissionError:
    sys.exit("needs root: sudo python3 " + sys.argv[0])


def P(b, off):
    os.pwrite(fd, bytes([b]), off)


def R(off):
    return os.pread(fd, 1, off)[0]


def ec_read(addr):
    P(0x2E, 0x4E); P(0x11, 0x4F)                    # command 0x11: high byte
    P(0x2F, 0x4E); P((addr >> 8) & 0xFF, 0x4F)
    P(0x2E, 0x4E); P(0x10, 0x4F)                    # command 0x10: low byte
    P(0x2F, 0x4E); P(addr & 0xFF, 0x4F)
    P(0x2E, 0x4E); P(0x12, 0x4F)                    # command 0x12: read
    P(0x2F, 0x4E)
    return R(0x4F)


lo = ec_read(0xC664)
hi = ec_read(0xC665)
print(f"RPM = {lo | (hi << 8)}  (lo=0x{lo:02x} hi=0x{hi:02x})")
