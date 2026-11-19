#!/usr/bin/env python3
"""Install the RemoteCompanion Antigravity Bridge extension into Antigravity IDE."""
import json
import os
import shutil
import subprocess
import sys
import time
import zipfile
from xml.sax.saxutils import escape

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
EXT_SRC_DIR = os.path.join(ROOT, "tools", "rc-antigravity-ext")
EXT_ROOT = os.path.expanduser("~/.antigravity-ide/extensions")
CLI_BIN = "/Applications/Antigravity IDE.app/Contents/Resources/app/bin/antigravity-ide"

CONTENT_TYPES_XML = """<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json" />
  <Default Extension=".js" ContentType="application/javascript" />
  <Default Extension=".vsixmanifest" ContentType="text/xml" />
</Types>
"""


def _build_vsix_manifest(pkg):
    publisher = escape(pkg["publisher"])
    name = escape(pkg["name"])
    version = escape(pkg["version"])
    display_name = escape(pkg.get("displayName", name))
    description = escape(pkg.get("description", ""))
    return f"""<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="{name}" Version="{version}" Publisher="{publisher}" />
    <DisplayName>{display_name}</DisplayName>
    <Description xml:space="preserve">{description}</Description>
    <Tags></Tags>
    <Categories>Other</Categories>
    <GalleryFlags>Public</GalleryFlags>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="{escape(pkg.get('engines', {}).get('vscode', '^1.68.0'))}" />
    </Properties>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code" />
  </Installation>
  <Dependencies />
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
  </Assets>
</PackageManifest>
"""


def _update_extensions_json(ext_id, version, dest_dir, rel_dir):
    json_path = os.path.join(EXT_ROOT, "extensions.json")
    try:
        with open(json_path, "r", encoding="utf-8") as f:
            entries = json.load(f)
        if not isinstance(entries, list):
            entries = []
    except (OSError, ValueError):
        entries = []

    now_ms = int(time.time() * 1000)
    new_entry = {
        "identifier": {"id": ext_id},
        "version": version,
        "location": {
            "$mid": 1,
            "fsPath": dest_dir,
            "external": f"file://{dest_dir}",
            "path": dest_dir,
            "scheme": "file",
        },
        "relativeLocation": rel_dir,
        "metadata": {
            "isApplicationScoped": False,
            "isMachineScoped": False,
            "isBuiltin": False,
            "installedTimestamp": now_ms,
            "pinned": True,
            "source": "vsix",
        },
    }

    updated = [
        item
        for item in entries
        if not (
            isinstance(item, dict)
            and isinstance(item.get("identifier"), dict)
            and item["identifier"].get("id") == ext_id
        )
    ]
    updated.append(new_entry)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(updated, f, separators=(",", ":"))


def _clear_obsolete(rel_dir):
    obsolete_path = os.path.join(EXT_ROOT, ".obsolete")
    if not os.path.exists(obsolete_path):
        return
    try:
        with open(obsolete_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict) and rel_dir in data:
            del data[rel_dir]
            with open(obsolete_path, "w", encoding="utf-8") as f:
                json.dump(data, f, separators=(",", ":"))
    except (OSError, ValueError):
        pass


def main():
    pkg_path = os.path.join(EXT_SRC_DIR, "package.json")
    ext_js_path = os.path.join(EXT_SRC_DIR, "extension.js")
    with open(pkg_path, "r", encoding="utf-8") as f:
        pkg = json.load(f)

    ext_id = f"{pkg['publisher']}.{pkg['name']}"
    version = pkg["version"]
    rel_dir = f"{ext_id}-{version}"
    dest_dir = os.path.join(EXT_ROOT, rel_dir)
    vsix_path = f"/tmp/{pkg['name']}-{version}.vsix"

    if os.path.isdir(EXT_ROOT):
        prefix = f"{ext_id}-"
        for entry in os.listdir(EXT_ROOT):
            if entry.startswith(prefix) and entry != rel_dir:
                old_path = os.path.join(EXT_ROOT, entry)
                if os.path.isdir(old_path):
                    shutil.rmtree(old_path, ignore_errors=True)

    os.makedirs(dest_dir, exist_ok=True)
    shutil.copy2(pkg_path, os.path.join(dest_dir, "package.json"))
    shutil.copy2(ext_js_path, os.path.join(dest_dir, "extension.js"))

    _update_extensions_json(ext_id, version, dest_dir, rel_dir)
    _clear_obsolete(rel_dir)

    with zipfile.ZipFile(vsix_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", CONTENT_TYPES_XML)
        zf.writestr("extension.vsixmanifest", _build_vsix_manifest(pkg))
        zf.write(pkg_path, "extension/package.json")
        zf.write(ext_js_path, "extension/extension.js")

    if os.path.exists(CLI_BIN):
        proc = subprocess.run(
            [CLI_BIN, "--install-extension", vsix_path, "--force"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        if proc.stdout:
            print(proc.stdout.strip())
        if proc.returncode != 0:
            print(f"Warning: antigravity-ide --install-extension exited {proc.returncode}", file=sys.stderr)
        _clear_obsolete(rel_dir)

    print(f"Installed {ext_id}@{version} -> {dest_dir}")


if __name__ == "__main__":
    main()
