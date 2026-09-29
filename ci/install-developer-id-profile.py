#!/usr/bin/env python3
"""Installs a manually managed Developer ID provisioning profile for DeskCast.

The Focus indicator's Communication Notifications entitlement needs a
profile, and automatic signing on a fresh CI runner creates a new Apple
Development certificate every run (until the account hits its limit). This
finds (or creates) a Developer ID ("MAC_APP_DIRECT") profile through the App
Store Connect API instead, installs it, and prints its name for
PROVISIONING_PROFILE_SPECIFIER.

Usage: install-developer-id-profile.py <key.p8> <key id> <issuer id>
Only the standard library and the openssl command line tool are used.
"""

from __future__ import annotations

import base64
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

BUNDLE_ID = "com.ahmetbugraozcan.screenshotapp"
PROFILE_NAME = "DeskCast Developer ID CI"
API = "https://api.appstoreconnect.apple.com/v1"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw_signature(der: bytes) -> bytes:
    """openssl writes ECDSA signatures as DER; JWT wants r || s (32 bytes each)."""
    def read_int(offset: int) -> tuple[bytes, int]:
        assert der[offset] == 0x02
        length = der[offset + 1]
        value = der[offset + 2:offset + 2 + length]
        return value.lstrip(b"\x00").rjust(32, b"\x00"), offset + 2 + length

    assert der[0] == 0x30
    offset = 3 if der[1] & 0x80 else 2
    r, offset = read_int(offset)
    s, _ = read_int(offset)
    return r + s


def make_token(key_path: str, key_id: str, issuer_id: str) -> str:
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(), capture_output=True, check=True
    ).stdout
    return f"{signing_input}.{b64url(der_to_raw_signature(der))}"


def request(token: str, path: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(
        path if path.startswith("http") else API + path,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST" if body else "GET",
    )
    try:
        with urllib.request.urlopen(req) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        sys.exit(f"App Store Connect API {error.code} for {path}: {error.read().decode()}")


def query(params: dict) -> str:
    return urllib.parse.urlencode(params)


def main() -> None:
    key_path, key_id, issuer_id = sys.argv[1:4]
    token = make_token(key_path, key_id, issuer_id)

    bundles = request(token, "/bundleIds?" + query({"filter[identifier]": BUNDLE_ID, "limit": 200}))["data"]
    bundle = next((b for b in bundles if b["attributes"]["identifier"] == BUNDLE_ID), None)
    if bundle is None:
        sys.exit(f"No bundle ID {BUNDLE_ID} in the account")

    certificates = [
        c for c in request(token, "/certificates?limit=200")["data"]
        if c["attributes"]["certificateType"].startswith("DEVELOPER_ID_APPLICATION")
    ]
    if not certificates:
        sys.exit("No Developer ID Application certificate in the account")
    certificate_ids = {c["id"] for c in certificates}

    profiles = request(token, "/profiles?" + query({"filter[name]": PROFILE_NAME, "limit": 200}))["data"]
    profile = None
    for candidate in profiles:
        attributes = candidate["attributes"]
        if attributes["name"] != PROFILE_NAME or attributes["profileState"] != "ACTIVE":
            continue
        linked = request(token, f"/profiles/{candidate['id']}/certificates?limit=200")["data"]
        if certificate_ids <= {c["id"] for c in linked}:
            profile = candidate
            break

    if profile is None:
        profile = request(token, "/profiles", {
            "data": {
                "type": "profiles",
                "attributes": {"name": PROFILE_NAME, "profileType": "MAC_APP_DIRECT"},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                    "certificates": {"data": [{"type": "certificates", "id": i} for i in sorted(certificate_ids)]},
                },
            }
        })["data"]
        print(f"Created profile {profile['attributes']['uuid']}", file=sys.stderr)

    content = base64.b64decode(profile["attributes"]["profileContent"])
    with tempfile.NamedTemporaryFile(suffix=".provisionprofile") as raw:
        raw.write(content)
        raw.flush()
        decoded = subprocess.run(["security", "cms", "-D", "-i", raw.name], capture_output=True, check=True).stdout
    entitlements = plistlib.loads(decoded).get("Entitlements", {})
    if "com.apple.developer.usernotifications.communication" not in entitlements:
        sys.exit("The profile lacks the Communication Notifications entitlement")

    uuid = profile["attributes"]["uuid"]
    for folder in ("~/Library/MobileDevice/Provisioning Profiles", "~/Library/Developer/Xcode/UserData/Provisioning Profiles"):
        path = os.path.expanduser(folder)
        os.makedirs(path, exist_ok=True)
        with open(os.path.join(path, f"{uuid}.provisionprofile"), "wb") as file:
            file.write(content)

    print(profile["attributes"]["name"])


if __name__ == "__main__":
    main()
