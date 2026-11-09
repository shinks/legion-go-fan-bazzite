#!/bin/bash
# fan full|auto|status -- firmware full-speed override (Legion Go 1, device GZFD)
# Requires acpi_call loaded. Needs root: writes to /proc/acpi/call.
C=/proc/acpi/call
read_call() { tr -d '\0' < "$C"; }
[ -w "$C" ] || { echo "acpi_call is not loaded (no $C)"; exit 1; }
case "${1:-status}" in
  full)   echo '\_SB.GZFD.WMAE 0x00 0x12 b0000020401000000' > "$C"; echo "full speed: $(read_call)" ;;
  auto)   echo '\_SB.GZFD.WMAE 0x00 0x12 b0000020400000000' > "$C"; echo "auto: $(read_call)" ;;
  status) echo '\_SB.GZFD.WMAE 0x00 0x11 b00000204'            > "$C"; echo "override: $(read_call)" ;;
  *) echo "usage: fan full|auto|status"; exit 2 ;;
esac
