"""macOS connectivity diagnostic. Does not accept or read account credentials."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--interface", help="Explicit physical interface, e.g. en0; otherwise use system routing")
args = parser.parse_args()
root = Path(__file__).resolve().parent
if not shutil.which("cargo"):
    raise SystemExit("Rust cargo is required for this development diagnostic.")
with tempfile.TemporaryDirectory(prefix="setu-ech-") as directory:
    directory = Path(directory)
    command = ["curl", "--noproxy", "*", "--proto", "=https", "--tlsv1.2", "--fail", "--silent", "--show-error", "--connect-timeout", "8", "--max-time", "20"]
    if args.interface:
        command += ["--interface", args.interface]
    command += ["https://223.5.5.5/resolve?name=cloudflare-ech.com&type=HTTPS"]
    payload = json.loads(subprocess.check_output(command))
    config = None
    for answer in payload.get("Answer", []):
        match = re.search(r'(?:^|\s)ech="?([A-Za-z0-9+/=]+)', answer.get("data", ""))
        if match:
            config = match.group(1)
            break
    if not config:
        raise SystemExit("Verified DNS response did not contain an ECH configuration.")
    config_file = directory / "ech.b64"
    config_file.write_text(config)
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")
    # Public protocol metadata, not a user token or application account secret.
    salt = "28c1fdd170a5204386cb1313c7077b34f83e4aaf4aa829ce78c231e05b0bae2c"
    headers_file = directory / "headers.json"
    headers_file.write_text(json.dumps({"X-Client-Time": now, "X-Client-Hash": hashlib.md5((now + salt).encode()).hexdigest()}))
    environment = dict(os.environ, ECH_PROBE_CONFIG=str(config_file), ECH_PROBE_HEADERS=str(headers_file))
    if args.interface:
        environment["ECH_PROBE_INTERFACE"] = args.interface
    else:
        environment.pop("ECH_PROBE_INTERFACE", None)
    for binary in ("setu-ech-probe", "http", "image"):
        command = ["cargo", "run", "--locked", "--manifest-path", str(root / "Cargo.toml"), "--bin", binary]
        if binary == "setu-ech-probe":
            command += ["--", str(config_file)]
        subprocess.run(command, env=environment, check=True)
