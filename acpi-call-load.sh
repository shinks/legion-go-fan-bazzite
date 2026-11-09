#!/bin/bash
# Build (if needed), sign and load acpi_call. Safe to run on every boot:
# if the module's vermagic does not match the running kernel, it recompiles
# and re-signs with the MOK stored in the same directory.
set -u
DIR=/var/lib/acpi-call
KO=$DIR/acpi_call.ko
SRC=$DIR/src
KVER=$(uname -r)
KDIR=/usr/src/kernels/$KVER

[ -e /proc/acpi/call ] && exit 0          # already loaded

need=0
[ -f "$KO" ] || need=1
if [ -f "$KO" ]; then
  vm=$(modinfo -F vermagic "$KO" 2>/dev/null | awk '{print $1}')
  [ "$vm" = "$KVER" ] || need=1
fi

if [ "$need" = 1 ]; then
  [ -d "$KDIR" ] || { echo "missing kernel-devel for $KVER ($KDIR)"; exit 1; }
  [ -d "$SRC" ] || git clone -q --depth 1 https://github.com/nix-community/acpi_call "$SRC" || exit 1
  make -C "$KDIR" M="$SRC" modules || exit 1
  "$KDIR"/scripts/sign-file sha256 "$DIR/MOK.key" "$DIR/MOK.crt" "$SRC/acpi_call.ko" || exit 1
  install -m644 "$SRC/acpi_call.ko" "$KO"
  chcon -t modules_object_t "$KO" 2>/dev/null
  logger -t acpi-call "rebuilt and signed for $KVER"
fi

insmod "$KO"
