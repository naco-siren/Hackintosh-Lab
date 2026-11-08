#!/usr/bin/env python3
"""One-shot SMBIOS generator (iMac18,1) using GenSMBIOS's bundled macserial.

Writes Source/smbios.local.plist (gitignored). Refuses to overwrite: an SMBIOS identity
must stay stable once the machine has signed in to iServices.

usage: gen_smbios.py <macserial> <out plist>
"""
import os
import plistlib
import secrets
import subprocess
import sys
import uuid

MODEL = "iMac18,1"


def main(macserial, out):
    if os.path.exists(out):
        sys.exit(f"{out} exists; delete it manually if you really want a new identity")
    line = subprocess.check_output([macserial, "-m", MODEL, "-g", "-n", "1"], text=True).strip()
    serial, mlb = (x.strip() for x in line.split("|"))
    assert len(serial) == 12 and len(mlb) == 17, "unexpected macserial output"
    # Onboard I219 reports a blank-NVM default MAC (same on many boards) under Linux, so it is not a
    # usable unique ROM. Use a random 6-byte ROM instead.
    data = {"SystemProductName": MODEL, "SystemSerialNumber": serial, "MLB": mlb,
            "SystemUUID": str(uuid.uuid4()).upper(), "ROM": secrets.token_bytes(6)}
    with open(out, "wb") as f:
        plistlib.dump(data, f)
    os.chmod(out, 0o600)
    print(f"SMBIOS {MODEL} written to {out} (serial check: https://checkcoverage.apple.com should say 'invalid')")


if __name__ == "__main__":
    main(*sys.argv[1:])
