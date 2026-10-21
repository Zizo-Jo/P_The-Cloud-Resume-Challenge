#!/usr/bin/env python3
"""Package each Lambda into build/<name>.zip.

The zips are reproducible: the same source always gives the same bytes, so
the same SHA-256. That matters twice:
  - the PR plan, the drift check and the deploy all build their own copy, and
    Terraform only sees "no change" if the hashes match;
  - the deploy signs a provenance attestation for that hash, and the hash
    Terraform uploads must be the one that was attested.
So: fixed timestamps, fixed permissions, sorted entries, no compression
(compressed output can differ between zlib versions).
"""
import hashlib
import pathlib
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"

# zip name -> source files (the handler module names must match Terraform)
LAMBDAS = {
    "counter": ["src/lambda/func.py"],
    "uptime": ["src/uptime/check.py"],
    "ops": ["src/ops/publisher.py"],
}


def build(name, sources):
    out = BUILD / f"{name}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as zf:
        for src in sorted(sources):
            path = ROOT / src
            info = zipfile.ZipInfo(path.name, date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = 0o644 << 16  # -rw-r--r--
            info.create_system = 3  # Unix, whatever OS builds it
            zf.writestr(info, path.read_bytes())
    return hashlib.sha256(out.read_bytes()).hexdigest()


if __name__ == "__main__":
    BUILD.mkdir(exist_ok=True)
    for name, sources in LAMBDAS.items():
        print(f"{build(name, sources)}  build/{name}.zip")
