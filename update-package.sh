#!/usr/bin/env bash
# Refresh sources.json from the signed Kiro Crew stable manifest and the
# Kiro CLI manifest, then verify the desktop package still builds.
# No argument = latest stable of each. See README.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_FILE="$SCRIPT_DIR/sources.json"
PUBLIC_KEY="$SCRIPT_DIR/cli-manifest-public.pem"
FEED_URL="https://updates.crew.kiro.dev/feed/stable/latest-cli.json"
ARTIFACT_BASE="https://download.crew.kiro.dev"
CHANNEL="stable"
# SHA-256 of the pinned PEM's DER encoding. Same trust root the official
# installer embeds. A swapped key fails here, before the feed is fetched.
EXPECTED_KEY_ID="d3a83f0c1ff84a2cbee6bd34d889d8725af34358148a6c18ed3ecbbbcceec06b"

if ! command -v openssl >/dev/null || ! command -v python3 >/dev/null; then
  echo "openssl and python3 are required." >&2
  exit 1
fi

key_id="$(openssl pkey -pubin -in "$PUBLIC_KEY" -outform DER | sha256sum | awk '{print $1}')"
if [ "$key_id" != "$EXPECTED_KEY_ID" ]; then
  echo "cli-manifest-public.pem fingerprint mismatch." >&2
  echo "  expected: ${EXPECTED_KEY_ID}" >&2
  echo "  got:      ${key_id}" >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

curl -fsSL --proto '=https' --max-filesize 65536 "$FEED_URL" -o "$workdir/cli-manifest.json"

python3 - "$workdir/cli-manifest.json" "$workdir/signed-payload.json" \
  "$workdir/manifest-signature.bin" "sha256:${EXPECTED_KEY_ID}" <<'PY'
import base64
import json
import sys

manifest_path, payload_path, signature_path, pinned_key_id = sys.argv[1:]
expected = {
    "algorithm", "channel", "key_id", "pub_date", "python_requires",
    "schema", "sha256", "signature", "version", "wheel_url",
}
optional = {"min_version"}

def no_duplicates(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate key")
        value[key] = item
    return value

raw = open(manifest_path, "rb").read(65537)
if len(raw) > 65536:
    raise SystemExit("oversized manifest")
manifest = json.loads(raw.decode("utf-8"), object_pairs_hook=no_duplicates)
if not isinstance(manifest, dict):
    raise SystemExit("manifest is not an object")
if not expected <= set(manifest) or set(manifest) - expected - optional:
    raise SystemExit(f"unexpected manifest fields: {sorted(set(manifest))}")
if not all(isinstance(value, str) and value for value in manifest.values()):
    raise SystemExit("invalid field type")
if manifest["schema"] != "kirocrew-cli-artifact-manifest-v1":
    raise SystemExit("unsupported schema")
if manifest["algorithm"] != "RSASSA_PKCS1_V1_5_SHA_256":
    raise SystemExit("unsupported algorithm")
if manifest["key_id"] != pinned_key_id:
    raise SystemExit("untrusted key id")
signature = base64.b64decode(manifest.pop("signature"), validate=True)
if not signature or len(signature) > 1024:
    raise SystemExit("invalid signature size")
canonical = (
    json.dumps(manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n"
).encode("ascii")
open(payload_path, "wb").write(canonical)
open(signature_path, "wb").write(signature)
PY

openssl dgst -sha256 -verify "$PUBLIC_KEY" \
  -signature "$workdir/manifest-signature.bin" "$workdir/signed-payload.json" \
  >/dev/null

NEW_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$workdir/signed-payload.json")"
CURRENT_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$SOURCES_FILE")"

case "$NEW_VERSION" in
  *[!A-Za-z0-9._+]*)
    echo "Refusing version ${NEW_VERSION}" >&2
    exit 1
    ;;
esac

X64_URL="${ARTIFACT_BASE}/desktop/${CHANNEL}/${NEW_VERSION}/KiroCrew-x86_64.AppImage"
ARM_URL="${ARTIFACT_BASE}/desktop/${CHANNEL}/${NEW_VERSION}/KiroCrew-aarch64.AppImage"

CLI_MANIFEST_URL="https://prod.download.cli.kiro.dev/stable/latest/manifest.json"
CLI_BASE="https://prod.download.cli.kiro.dev/stable"

echo "Fetching Kiro CLI manifest..."
curl -fsSL --proto '=https' --max-filesize 1048576 "$CLI_MANIFEST_URL" -o "$workdir/kiro-cli-manifest.json"

python3 - "$workdir/kiro-cli-manifest.json" "$CLI_BASE" <<'PY' > "$workdir/cli-pin.json"
import json
import sys

manifest_path, base = sys.argv[1:]
manifest = json.load(open(manifest_path, encoding="utf-8"))
version = manifest.get("version")
if not isinstance(version, str) or not version:
    raise SystemExit("Kiro CLI manifest has no version")
packages = manifest.get("packages")
if not isinstance(packages, list):
    raise SystemExit("Kiro CLI manifest has no packages")

wanted = {}
for package in packages:
    if not isinstance(package, dict):
        continue
    if package.get("fileType") != "zip" or package.get("variant") != "headless":
        continue
    triple = package.get("targetTriple") or ""
    if not triple.endswith("-gnu"):
        continue
    arch = package.get("architecture")
    if arch not in ("x86_64", "aarch64") or arch in wanted:
        continue
    download = package.get("download")
    digest = package.get("sha256")
    if not isinstance(download, str) or not isinstance(digest, str):
        raise SystemExit(f"bad package entry for {arch}")
    if ".." in download or download.startswith("/"):
        raise SystemExit(f"refusing download path {download}")
    wanted[arch] = {
        "url": f"{base}/{download}",
        "sha256": digest,
    }

missing = [arch for arch in ("x86_64", "aarch64") if arch not in wanted]
if missing:
    raise SystemExit(f"Kiro CLI manifest is missing gnu zip for {', '.join(missing)}")

json.dump({"version": version, "sources": wanted}, sys.stdout)
PY

CLI_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$workdir/cli-pin.json")"
CURRENT_CLI="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["kiroCli"]["version"])' "$SOURCES_FILE")"

case "$CLI_VERSION" in
  *[!A-Za-z0-9._+]*)
    echo "Refusing Kiro CLI version ${CLI_VERSION}" >&2
    exit 1
    ;;
esac

if [ "$NEW_VERSION" = "$CURRENT_VERSION" ] && [ "$CLI_VERSION" = "$CURRENT_CLI" ]; then
  echo "Already up to date (kirocrew-desktop ${CURRENT_VERSION}, kiro-cli ${CURRENT_CLI})."
  exit 0
fi

prefetch() {
  nix store prefetch-file --json --hash-type sha256 "$1"
}

sri_hash() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)["hash"])'
}

# Manifest sha256 is hex. Confirm the prefetched file matches before
# accepting the SRI hash Nix will pin.
verify_sha256() {
  local path="$1" expected="$2" got
  got="$(python3 -c 'import hashlib,pathlib,sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())' "$path")"
  if [ "$got" != "$expected" ]; then
    echo "sha256 mismatch for ${path}" >&2
    echo "  expected: ${expected}" >&2
    echo "  got:      ${got}" >&2
    exit 1
  fi
}

if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
  echo "Updating kirocrew-desktop: ${CURRENT_VERSION} -> ${NEW_VERSION}"
  echo "  x86_64-linux: ${X64_URL}"
  echo "  aarch64-linux: ${ARM_URL}"
  echo "Prefetching x86_64 AppImage..."
  X64_HASH="$(prefetch "$X64_URL" | sri_hash)"
  echo "Prefetching aarch64 AppImage..."
  ARM_HASH="$(prefetch "$ARM_URL" | sri_hash)"
else
  echo "kirocrew-desktop ${CURRENT_VERSION} is current."
  X64_HASH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sources"]["x86_64-linux"]["hash"])' "$SOURCES_FILE")"
  ARM_HASH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sources"]["aarch64-linux"]["hash"])' "$SOURCES_FILE")"
fi

if [ "$CLI_VERSION" != "$CURRENT_CLI" ]; then
  echo "Updating kiro-cli: ${CURRENT_CLI} -> ${CLI_VERSION}"
  CLI_X64_URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sources"]["x86_64"]["url"])' "$workdir/cli-pin.json")"
  CLI_ARM_URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sources"]["aarch64"]["url"])' "$workdir/cli-pin.json")"
  CLI_X64_SHA="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sources"]["x86_64"]["sha256"])' "$workdir/cli-pin.json")"
  CLI_ARM_SHA="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sources"]["aarch64"]["sha256"])' "$workdir/cli-pin.json")"
  echo "  x86_64-linux: ${CLI_X64_URL}"
  echo "  aarch64-linux: ${CLI_ARM_URL}"
  echo "Prefetching x86_64 Kiro CLI..."
  CLI_X64_JSON="$(prefetch "$CLI_X64_URL")"
  verify_sha256 "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["storePath"])' "$CLI_X64_JSON")" "$CLI_X64_SHA"
  CLI_X64_HASH="$(printf '%s' "$CLI_X64_JSON" | sri_hash)"
  echo "Prefetching aarch64 Kiro CLI..."
  CLI_ARM_JSON="$(prefetch "$CLI_ARM_URL")"
  verify_sha256 "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["storePath"])' "$CLI_ARM_JSON")" "$CLI_ARM_SHA"
  CLI_ARM_HASH="$(printf '%s' "$CLI_ARM_JSON" | sri_hash)"
else
  echo "kiro-cli ${CURRENT_CLI} is current."
  CLI_X64_URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["kiroCli"]["sources"]["x86_64-linux"]["url"])' "$SOURCES_FILE")"
  CLI_ARM_URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["kiroCli"]["sources"]["aarch64-linux"]["url"])' "$SOURCES_FILE")"
  CLI_X64_HASH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["kiroCli"]["sources"]["x86_64-linux"]["hash"])' "$SOURCES_FILE")"
  CLI_ARM_HASH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["kiroCli"]["sources"]["aarch64-linux"]["hash"])' "$SOURCES_FILE")"
fi

python3 - "$SOURCES_FILE" "$NEW_VERSION" "$X64_URL" "$X64_HASH" "$ARM_URL" "$ARM_HASH" \
  "$CLI_VERSION" "$CLI_X64_URL" "$CLI_X64_HASH" "$CLI_ARM_URL" "$CLI_ARM_HASH" <<'PY'
import json
import sys

(
    path,
    version,
    x64_url,
    x64_hash,
    arm_url,
    arm_hash,
    cli_version,
    cli_x64_url,
    cli_x64_hash,
    cli_arm_url,
    cli_arm_hash,
) = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "version": version,
            "sources": {
                "x86_64-linux": {"url": x64_url, "hash": x64_hash},
                "aarch64-linux": {"url": arm_url, "hash": arm_hash},
            },
            "kiroCli": {
                "version": cli_version,
                "sources": {
                    "x86_64-linux": {"url": cli_x64_url, "hash": cli_x64_hash},
                    "aarch64-linux": {"url": cli_arm_url, "hash": cli_arm_hash},
                },
            },
        },
        handle,
        indent=2,
    )
    handle.write("\n")
PY

echo "Wrote ${SOURCES_FILE}"
echo "Building package to verify..."
nix build "${SCRIPT_DIR}#default" --no-link
RESULT_PATH="$(nix build "${SCRIPT_DIR}#kiro-cli" --no-link --print-out-paths)"
echo "Built kiro-cli: ${RESULT_PATH}"
"$RESULT_PATH/bin/kiro-cli" --version
echo
echo "sources.json now points at kirocrew-desktop ${NEW_VERSION} and kiro-cli ${CLI_VERSION}."
echo "Review the diff before committing:"
echo "  git -C \"${SCRIPT_DIR}\" diff sources.json"
