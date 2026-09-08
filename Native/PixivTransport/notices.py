"""Collect license texts from the locked Apple dependency graph, without network access."""
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent
metadata = json.loads(subprocess.check_output([
    sys.argv[1], "metadata", "--locked", "--offline", "--format-version", "1",
    "--filter-platform", "aarch64-apple-ios", "--manifest-path", str(root / "Cargo.toml"),
]))
used = {node["id"] for node in metadata["resolve"]["nodes"]}
sections = ["Setu Pixiv Transport - Third-party notices\nGenerated from Cargo.lock.\n"]
for package in sorted(metadata["packages"], key=lambda item: (item["name"], item["version"])):
    if package["id"] not in used or package["name"] == "setu-pixiv-transport":
        continue
    directory = pathlib.Path(package["manifest_path"]).parent
    texts = sorted(path for path in directory.rglob("*") if path.is_file()
                   and path.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE"))
                   and path.suffix.lower() not in (".rs", ".go", ".py", ".pl", ".html"))
    sections.append(f"\n{'=' * 72}\n{package['name']} {package['version']}\n"
                    f"License: {package.get('license') or 'See included text'}\n"
                    f"Source: {package.get('repository') or package['source']}\n")
    if not texts:
        directory = root / "licenses" / package["name"]
        texts = sorted(path for path in directory.glob("LICENSE*") if path.is_file())
        if not texts:
            raise SystemExit(f"Missing license text: {package['name']}")
    for path in texts:
        sections.append(f"\n--- {path.relative_to(directory)} ---\n{path.read_text(errors='replace')}\n")
(root / "build" / "ThirdPartyNotices.txt").write_text("".join(sections))
