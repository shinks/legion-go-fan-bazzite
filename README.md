# Legion Go 1 fan control on Bazzite — full speed without HHD

Bazzite has no fan UI for the Legion Go (HHD was dropped in Bazzite 44, PowerStation only handles
TDP), and the usual conclusion is that the fan is locked. It is not: the firmware exposes a
**full-speed override** — the same mechanism Legion Space and Handheld Daemon use — and it works on
the original Go (83E1) under Bazzite.

Measured on a Legion Go 83E1, Bazzite 45, kernel `7.2.15-ogc1.1.fc45`, BIOS v40:

| Fan state | RPM |
|---|---|
| Firmware automatic curve | 4,501 – 4,597 |
| Full-speed override | **7,986 – 8,325** |

That ~78 % difference is what keeps the console from shutting down from heat in demanding games.

## The ACPI interface

Device `GZFD`, method `WMAE`, feature `0x04020000`, written to `/proc/acpi/call`:

| Action | Call |
|---|---|
| Read state | `\_SB.GZFD.WMAE 0x00 0x11 b00000204` → `0x0` off / `0x1` on |
| Full speed ON | `\_SB.GZFD.WMAE 0x00 0x12 b0000020401000000` |
| Full speed OFF | `\_SB.GZFD.WMAE 0x00 0x12 b0000020400000000` |

The payload is feature (4 bytes LE) + value (4 bytes LE) as hex with a `b` prefix. The reply ends
with a null byte — strip it with `tr -d '\0'`.

## Why it takes more than "just load acpi_call"

`acpi_call` is not shipped in Bazzite: it must be built against the running kernel's `kernel-devel`
(Bazzite ships a matching NEVRA, so no layering or akmods are needed). Then two independent gates
must be opened, and **they fail with different messages**:

| Gate | Error | Fix |
|---|---|---|
| Secure Boot | `insmod: Key was rejected by service` | sign with your own MOK, `mokutil --import`, enroll in MokManager |
| SELinux | `insmod: Permission denied` | `chcon -t modules_object_t` + `semanage fcontext` |

The SELinux gate only shows up **after a reboot**: a module loaded by hand right after signing
works, and the next boot fails. `lockdown=none` does not mean unsigned modules load, and a valid
signature does not mean the module loads when the label is wrong.

## Install

```bash
sudo mkdir -p /var/lib/acpi-call && cd /var/lib/acpi-call
git clone --depth 1 https://github.com/nix-community/acpi_call src
sudo make -C /usr/src/kernels/$(uname -r) M=/var/lib/acpi-call/src modules

sudo openssl req -new -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout MOK.key -out MOK.crt -subj "/CN=Legion Fan Control MOK/"
sudo openssl x509 -in MOK.crt -out MOK.cer -outform DER
sudo /usr/src/kernels/$(uname -r)/scripts/sign-file sha256 \
  /var/lib/acpi-call/MOK.key /var/lib/acpi-call/MOK.crt /var/lib/acpi-call/src/acpi_call.ko
sudo install -m644 /var/lib/acpi-call/src/acpi_call.ko /var/lib/acpi-call/acpi_call.ko

sudo chcon -t modules_object_t /var/lib/acpi-call/acpi_call.ko
sudo semanage fcontext -a -t modules_object_t "/var/lib/acpi-call/.*\.ko"

sudo mokutil --import /var/lib/acpi-call/MOK.cer   # invented, one-time password
sudo reboot   # MokManager: Enroll MOK -> Continue -> Yes -> password -> Reboot
```

Then install the pieces from this repo:

```bash
sudo install -m755 fan fan-guard rpm_ec.py /usr/local/bin/
sudo install -m644 acpi-call.service fan-guard.service /etc/systemd/system/
sudo install -m755 acpi-call-load.sh /usr/local/bin/
sudo systemctl daemon-reload
sudo systemctl enable --now acpi-call.service
```

`acpi-call-load.sh` checks the module's `vermagic` on every boot and rebuilds + re-signs
automatically when a kernel update invalidates it — that is the part that makes this survive
`rpm-ostree upgrade`.

Optional thermal guard (full above 80 °C, back to automatic below 65 °C):

```bash
sudo systemctl enable --now fan-guard.service
```

MokManager note: a 2.4 GHz dongle in the Legion Go's **bottom** USB-C port does not enumerate in
pre-boot (it works fine in the OS). Use the top port or a wired keyboard.

## Verify

```bash
ls -l /proc/acpi/call && systemctl is-active acpi-call
sudo fan full && sleep 15 && sudo python3 /usr/local/bin/rpm_ec.py    # ~8,000 RPM
sudo fan auto && sleep 25 && sudo python3 /usr/local/bin/rpm_ec.py    # ~4,500 RPM
```

`rpm_ec.py` reads EC register `0xC664` (16-bit LE) through `/dev/port` ports `0x4E/0x4F`.
`yogafan.ko` is in the kernel but does not expose `fan1_input` on this firmware, so the EC is the
only reliable RPM source.

## Files

- `acpi-call-load.sh` — build/sign/load with vermagic check (boot-safe)
- `acpi-call.service` — systemd unit calling the loader
- `fan` — `full|auto|status` toggle
- `fan-guard`, `fan-guard.service` — optional thermal daemon
- `rpm_ec.py` — EC RPM reader

## Credits

- [`everancii/Legion-Go-1-Fan-Control`](https://github.com/everancii/Legion-Go-1-Fan-Control)
  (fork of `Rodpad/LeGo2-Fan-Control-Decky` by Luke Cama, GPL-3.0): the `WMAE` calls and the EC
  map originate there.
- [`nix-community/acpi_call`](https://github.com/nix-community/acpi_call): the module.
- HHD / Legion Space: the override mechanism itself.

Tested only on a Legion Go 1 (83E1), BIOS v40. The Go 2 has real RPM control (`WMAB`), so none of
this applies there.
