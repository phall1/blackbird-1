#!/bin/sh
# Download, SHA-256 verify, smoke-check, and atomically install a prebuilt Blackbird release.
# Usage: curl -fsSL https://github.com/antimemeai/blackbird/releases/latest/download/install-release.sh | sh
set -eu

blackbird_version=${BLACKBIRD_VERSION:-latest}
blackbird_prefix=${BLACKBIRD_PREFIX:-}
blackbird_base_url=${BLACKBIRD_RELEASE_BASE_URL:-}

blackbird_usage() {
  cat <<'USAGE'
Usage:
  install-release.sh [--version <vX.Y.Z|latest>] [--prefix DIR] [--base-url URL]
  install-release.sh --help

Install a SHA-256 verified prebuilt Blackbird release atomically into
<prefix>/lib/blackbird/releases/generation-XXXXXXXX and switch
<prefix>/lib/blackbird/current + <prefix>/bin/blackbird.

Environment overrides:
  BLACKBIRD_VERSION           Release version tag or 'latest' (default: latest)
  BLACKBIRD_PREFIX            Install prefix (default: $HOME/.local)
  BLACKBIRD_RELEASE_BASE_URL  Release asset base URL (https:// or file:// only)
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version|--prefix|--base-url)
      [ "$#" -ge 2 ] || { printf 'Missing value for %s\n' "$1" >&2; exit 2; }
      case "$1" in
        --version) blackbird_version=$2 ;;
        --prefix) blackbird_prefix=$2 ;;
        --base-url) blackbird_base_url=$2 ;;
      esac
      shift 2 ;;
    --help|-h)
      blackbird_usage
      exit 0 ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 2 ;;
  esac
done

# Replace a symlink to a directory atomically, choosing the flag by mv flavour
# rather than OS: GNU mv (Linux, and macOS with Homebrew coreutils on PATH)
# spells it -T, BSD mv spells it -h.
blackbird_replace_symlink() {
  if mv --version >/dev/null 2>&1; then
    mv -fT -- "$1" "$2"
  else
    mv -fh -- "$1" "$2"
  fi
}
blackbird_validate_version() {
  bb_v=$1
  case "$bb_v" in
    latest) return 0 ;;
    ''|v|*..*|*/*) return 1 ;;
  esac
  # Locale-independent strict ASCII allowlist: v followed by [0-9A-Za-z._-]+.
  case "$bb_v" in
    v*[!0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._-]*) return 1 ;;
    v*) return 0 ;;
    *) return 1 ;;
  esac
}

if ! blackbird_validate_version "$blackbird_version"; then
  printf 'Unsafe or invalid version (expected latest or v[0-9A-Za-z._-]+): %s\n' "$blackbird_version" >&2
  exit 2
fi

if [ -z "$blackbird_prefix" ]; then
  blackbird_prefix=${HOME:?HOME must be set}/.local
fi

bb_nl='
'
case "$blackbird_prefix" in
  ''|*"$bb_nl"*)
    printf 'Unsafe or empty --prefix containing newline.\n' >&2
    exit 2 ;;
esac
if printf '%s' "$blackbird_prefix" | LC_ALL=C grep -q '[[:cntrl:]]'; then
  printf 'Unsafe --prefix containing control characters.\n' >&2
  exit 2
fi

if [ -z "$blackbird_base_url" ]; then
  if [ "$blackbird_version" = latest ]; then
    blackbird_base_url='https://github.com/antimemeai/blackbird/releases/latest/download'
  else
    blackbird_base_url="https://github.com/antimemeai/blackbird/releases/download/$blackbird_version"
  fi
fi

# Strip a single or multiple trailing slashes cleanly.
while :; do
  case "$blackbird_base_url" in
    */) blackbird_base_url=${blackbird_base_url%/} ;;
    *) break ;;
  esac
done

# Reject control characters and enforce https:// or file:// scheme ONLY.
case "$blackbird_base_url" in
  *"$bb_nl"*)
    printf 'Unsafe base URL containing newline.\n' >&2
    exit 2 ;;
esac
if printf '%s' "$blackbird_base_url" | LC_ALL=C grep -q '[[:cntrl:]]'; then
  printf 'Unsafe base URL containing control characters.\n' >&2
  exit 2
fi
case "$blackbird_base_url" in
  https://?*)
    case "$blackbird_base_url" in
      *' '*|*'	'*)
        printf 'Unsafe https:// base URL containing whitespace.\n' >&2
        exit 2 ;;
    esac ;;
  file://?*) ;;
  *)
    printf 'Refusing unsupported or insecure base URL (only https:// and file:// are allowed): %s\n' "$blackbird_base_url" >&2
    exit 2 ;;
esac

blackbird_os=$(uname -s)
case "$blackbird_os" in
  Darwin) blackbird_os_slug=darwin ;;
  Linux) blackbird_os_slug=linux ;;
  *)
    printf 'Unsupported operating system: %s\n' "$blackbird_os" >&2
    exit 1 ;;
esac

blackbird_arch=$(uname -m)
case "$blackbird_arch" in
  arm64|aarch64) blackbird_arch_slug=arm64 ;;
  x86_64|amd64) blackbird_arch_slug=x86_64 ;;
  *)
    printf 'Unsupported CPU architecture: %s\n' "$blackbird_arch" >&2
    exit 1 ;;
esac
blackbird_target="${blackbird_os_slug}-${blackbird_arch_slug}"

blackbird_fetch() {
  bb_url=$1
  bb_dest=$2
  case "$bb_url" in
    file://*)
      bb_src_path=${bb_url#file://}
      if [ ! -f "$bb_src_path" ]; then
        printf 'Local release asset not found: %s\n' "$bb_src_path" >&2
        return 1
      fi
      cp -- "$bb_src_path" "$bb_dest"
      ;;
    https://*)
      if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --tlsv1.2 -o "$bb_dest" "$bb_url"
      elif command -v wget >/dev/null 2>&1; then
        wget --https-only --secure-protocol=TLSv1_2 -qO "$bb_dest" "$bb_url"
      else
        printf 'Neither curl nor wget is available to download release assets.\n' >&2
        return 1
      fi
      ;;
    *)
      printf 'Refusing disallowed URL scheme: %s\n' "$bb_url" >&2
      return 1 ;;
  esac
}

blackbird_sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print tolower($1)}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | awk '{print tolower($1)}'
  else
    printf 'Neither sha256sum nor shasum is available for SHA-256 verification.\n' >&2
    return 1
  fi
}

blackbird_is_hex64() {
  case "$1" in
    *[!0123456789abcdefABCDEF]*) return 1 ;;
  esac
  [ "${#1}" -eq 64 ]
}

# Unified cleanup state for both temp workspace and atomic install transaction.
blackbird_tmp=''
blackbird_home=''
blackbird_lock_held=false
blackbird_generation=''
blackbird_link=''
blackbird_launcher=''
blackbird_previous_launcher=''
blackbird_launcher_published=false
blackbird_activated=false

blackbird_cleanup() {
  if [ -n "$blackbird_tmp" ]; then
    rm -rf -- "$blackbird_tmp"
  fi
  if [ -n "$blackbird_link" ]; then
    rm -f -- "$blackbird_link"
  fi
  if [ -n "$blackbird_launcher" ]; then
    rm -f -- "$blackbird_launcher"
  fi
  if [ -n "$blackbird_home" ] && [ -n "$blackbird_generation" ] &&
     [ "$(readlink "$blackbird_home/current" 2>/dev/null || :)" = "$blackbird_generation" ]; then
    blackbird_activated=true
  fi
  if ! "$blackbird_activated"; then
    if "$blackbird_launcher_published"; then
      if [ -n "$blackbird_previous_launcher" ]; then
        mv -f -- "$blackbird_previous_launcher" "$blackbird_prefix/bin/blackbird"
        blackbird_previous_launcher=''
      else
        rm -f -- "$blackbird_prefix/bin/blackbird"
      fi
    fi
    if [ -n "$blackbird_generation" ]; then
      rm -rf -- "$blackbird_generation"
    fi
  fi
  if [ -n "$blackbird_previous_launcher" ]; then
    rm -f -- "$blackbird_previous_launcher"
  fi
  if "$blackbird_lock_held" && [ -n "$blackbird_home" ]; then
    rmdir -- "$blackbird_home/install.lock" 2>/dev/null || :
  fi
}
trap blackbird_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

blackbird_tmp=$(umask 077 && mktemp -d "${TMPDIR:-/tmp}/blackbird-release-XXXXXXXX")
chmod 700 "$blackbird_tmp"

# Step 1: Download SHA256SUMS.txt and resolve exact artifact + checksum BEFORE downloading tarball.
blackbird_sums_file="$blackbird_tmp/SHA256SUMS.txt"
blackbird_fetch "$blackbird_base_url/SHA256SUMS.txt" "$blackbird_sums_file" || {
  printf 'Failed to fetch SHA256SUMS.txt from %s\n' "$blackbird_base_url" >&2
  exit 1
}

blackbird_expected_sha=''
blackbird_tarball_name=''
blackbird_resolved_version=''
blackbird_match_count=0

while IFS= read -r bb_line || [ -n "$bb_line" ]; do
  # Strip optional CR from CRLF files.
  bb_line=$(printf '%s' "$bb_line" | tr -d '\r')
  [ -n "$bb_line" ] || continue
  # Parse "<64-hex>  <filename>" (optional leading '*' on filename in binary mode).
  bb_hash=${bb_line%%[ 	]*}
  bb_rest=${bb_line#"$bb_hash"}
  bb_file=$(printf '%s' "$bb_rest" | sed 's/^[ 	]*\*\{0,1\}//')
  [ -n "$bb_hash" ] && [ -n "$bb_file" ] || continue
  blackbird_is_hex64 "$bb_hash" || continue
  case "$bb_file" in
    */*|*..*|*' '*|*'	'*) continue ;;
  esac

  if [ "$blackbird_version" = latest ]; then
    case "$bb_file" in
      "blackbird-"*"-${blackbird_target}.tar.gz")
        bb_cand_ver=${bb_file#blackbird-}
        bb_cand_ver=${bb_cand_ver%-"${blackbird_target}".tar.gz}
        if [ "$bb_cand_ver" != latest ] && blackbird_validate_version "$bb_cand_ver"; then
          blackbird_match_count=$((blackbird_match_count + 1))
          blackbird_tarball_name=$bb_file
          blackbird_expected_sha=$(printf '%s' "$bb_hash" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
          blackbird_resolved_version=$bb_cand_ver
        fi
        ;;
    esac
  else
    bb_want="blackbird-${blackbird_version}-${blackbird_target}.tar.gz"
    if [ "$bb_file" = "$bb_want" ]; then
      blackbird_match_count=$((blackbird_match_count + 1))
      blackbird_tarball_name=$bb_file
      blackbird_expected_sha=$(printf '%s' "$bb_hash" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
      blackbird_resolved_version=$blackbird_version
    fi
  fi
done < "$blackbird_sums_file"

if [ "$blackbird_match_count" -eq 0 ]; then
  printf 'No matching SHA256SUMS.txt entry for version=%s target=%s\n' "$blackbird_version" "$blackbird_target" >&2
  exit 1
fi
if [ "$blackbird_match_count" -gt 1 ]; then
  printf 'Ambiguous SHA256SUMS.txt: multiple entries matched target=%s\n' "$blackbird_target" >&2
  exit 1
fi

blackbird_stem="blackbird-${blackbird_resolved_version}-${blackbird_target}"
blackbird_tarball_path="$blackbird_tmp/$blackbird_tarball_name"

# Step 2: Download tarball and verify SHA-256 strictly BEFORE tar -xzf or touching $prefix.
blackbird_fetch "$blackbird_base_url/$blackbird_tarball_name" "$blackbird_tarball_path" || {
  printf 'Failed to fetch %s from %s\n' "$blackbird_tarball_name" "$blackbird_base_url" >&2
  exit 1
}

blackbird_actual_sha=$(blackbird_sha256_file "$blackbird_tarball_path")
if ! blackbird_is_hex64 "$blackbird_actual_sha"; then
  printf 'Failed to compute valid SHA-256 digest for %s\n' "$blackbird_tarball_name" >&2
  exit 1
fi
if [ "$blackbird_actual_sha" != "$blackbird_expected_sha" ]; then
  printf 'SHA-256 mismatch for %s!\n  expected: %s\n  actual:   %s\n' \
    "$blackbird_tarball_name" "$blackbird_expected_sha" "$blackbird_actual_sha" >&2
  exit 1
fi

# Step 3: Validate every tar archive member path, type, and link target BEFORE tar -xzf.
blackbird_tar_list="$blackbird_tmp/tar.list"
blackbird_tar_vlist="$blackbird_tmp/tar.vlist"
tar -tzf "$blackbird_tarball_path" > "$blackbird_tar_list"
tar -tvzf "$blackbird_tarball_path" > "$blackbird_tar_vlist"
if [ ! -s "$blackbird_tar_list" ] || [ ! -s "$blackbird_tar_vlist" ]; then
  printf 'Refusing empty release tarball: %s\n' "$blackbird_tarball_name" >&2
  exit 1
fi
while IFS= read -r bb_entry || [ -n "$bb_entry" ]; do
  [ -n "$bb_entry" ] || continue
  case "$bb_entry" in
    /*|..|../*|*/..|*/../*)
      printf 'Refusing unsafe tarball entry: %s\n' "$bb_entry" >&2
      exit 1 ;;
    "$blackbird_stem"|"$blackbird_stem"/*) ;;
    *)
      printf 'Refusing tarball entry outside %s/: %s\n' "$blackbird_stem" "$bb_entry" >&2
      exit 1 ;;
  esac
done < "$blackbird_tar_list"

# Reject all hardlinks, special files, and any symlink outside <stem>/lib/ or with path traversal.
while IFS= read -r bb_vline || [ -n "$bb_vline" ]; do
  [ -n "$bb_vline" ] || continue
  case "$bb_vline" in
    -*|d*) ;;
    h*)
      printf 'Refusing hardlink in release tarball: %s\n' "$bb_vline" >&2
      exit 1 ;;
    l*)
      case "$bb_vline" in
        *" -> "*" -> "*)
          printf 'Refusing ambiguous symlink in release tarball: %s\n' "$bb_vline" >&2
          exit 1 ;;
        *" ${blackbird_stem}/lib/"?*" -> "?*)
          bb_sym_target=${bb_vline#*" -> "}
          bb_sym_prefix=${bb_vline%" -> "*}
          bb_sym_rel=${bb_sym_prefix##*" ${blackbird_stem}/lib/"}
          case "$bb_sym_rel" in
            ''|.|..|*/*|*..*)
              printf 'Refusing unsafe symlink path in release tarball: %s\n' "$bb_vline" >&2
              exit 1 ;;
          esac
          case "$bb_sym_target" in
            ''|.|..|*/*|*..*)
              printf 'Refusing unsafe symlink target in release tarball: %s\n' "$bb_vline" >&2
              exit 1 ;;
          esac
          ;;
        *)
          printf 'Refusing symlink outside %s/lib/ in release tarball: %s\n' "$blackbird_stem" "$bb_vline" >&2
          exit 1 ;;
      esac ;;
    *)
      printf 'Refusing unsupported entry type in release tarball: %s\n' "$bb_vline" >&2
      exit 1 ;;
  esac
done < "$blackbird_tar_vlist"

mkdir -p -- "$blackbird_tmp/extract"
tar -xzf "$blackbird_tarball_path" -C "$blackbird_tmp/extract"
blackbird_payload="$blackbird_tmp/extract/$blackbird_stem"

for bb_req in bin/blackbird scripts/blackbird share/blackbird/programs/turn.lua share/blackbird/assets/sr71.png share/blackbird/profiles/providers/conservative.lua MANIFEST; do
  if [ ! -f "$blackbird_payload/$bb_req" ]; then
    printf 'Incomplete release payload: missing %s\n' "$bb_req" >&2
    exit 1
  fi
done

# Step 4: Acquire install lock and stage atomically (matching scripts/install-blackbird).
mkdir -p -- "$blackbird_prefix"
blackbird_prefix=$(CDPATH= cd -- "$blackbird_prefix" && pwd -P)
blackbird_home=$blackbird_prefix/lib/blackbird
mkdir -p -- "$blackbird_home/releases" "$blackbird_prefix/bin"

mkdir -- "$blackbird_home/install.lock" 2>/dev/null || {
  printf 'Another install holds %s/install.lock (remove only after that installer exits).\n' "$blackbird_home" >&2
  exit 1
}
blackbird_lock_held=true

if [ -e "$blackbird_prefix/bin/blackbird" ] || [ -L "$blackbird_prefix/bin/blackbird" ]; then
  if [ -L "$blackbird_prefix/bin/blackbird" ] ||
     [ "$(sed -n '2p' "$blackbird_prefix/bin/blackbird")" != '# blackbird managed launcher v1' ]; then
    printf 'Refusing to replace unrelated launcher: %s/bin/blackbird\n' "$blackbird_prefix" >&2
    exit 1
  fi
fi
if [ -e "$blackbird_home/current" ] && [ ! -L "$blackbird_home/current" ]; then
  printf 'Refusing to replace non-symlink: %s/current\n' "$blackbird_home" >&2
  exit 1
fi

blackbird_generation=$(mktemp -d "$blackbird_home/releases/generation-XXXXXXXX")
cp -Rp -- "$blackbird_payload/bin" "$blackbird_payload/share" "$blackbird_payload/scripts" "$blackbird_payload/MANIFEST" "$blackbird_generation/"
if [ -d "$blackbird_payload/lib" ]; then
  cp -Rp -- "$blackbird_payload/lib" "$blackbird_generation/"
fi
chmod 755 "$blackbird_generation/scripts/blackbird" "$blackbird_generation/bin/blackbird"

if ! grep -q '^installed_at=' "$blackbird_generation/MANIFEST" 2>/dev/null; then
  printf 'installed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$blackbird_generation/MANIFEST"
fi

# Step 5: Offline smoke check BEFORE activation; prior generation stays untouched on failure.
mkdir -m 700 "$blackbird_generation/.smoke" "$blackbird_generation/.smoke/home" "$blackbird_generation/.smoke/auth"
blackbird_bin_version=$(
  HOME="$blackbird_generation/.smoke/home" \
  BLACKBIRD_AUTH_HOME="$blackbird_generation/.smoke/auth" \
  "$blackbird_generation/bin/blackbird" --version
)
case "$blackbird_bin_version" in
  blackbird\ *) ;;
  *)
    printf 'Unexpected --version output: %s\n' "$blackbird_bin_version" >&2
    exit 1 ;;
esac
HOME="$blackbird_generation/.smoke/home" \
BLACKBIRD_AUTH_HOME="$blackbird_generation/.smoke/auth" \
  "$blackbird_generation/bin/blackbird" --help > "$blackbird_generation/.smoke/help"
if [ ! -s "$blackbird_generation/.smoke/help" ]; then
  printf 'Offline smoke check failed: bin/blackbird --help produced empty output.\n' >&2
  exit 1
fi
rm -rf -- "$blackbird_generation/.smoke"

# Step 6: Publish managed launcher v1 and atomically swap current symlink.
blackbird_quoted_home=$(printf '%s' "$blackbird_home" | sed "s/'/'\\\\''/g")
blackbird_launcher=$(mktemp "$blackbird_prefix/bin/.blackbird-XXXXXXXX")
{
  printf '#!/bin/sh\n# blackbird managed launcher v1\nset -eu\n'
  printf "blackbird_install_home='%s'\n" "$blackbird_quoted_home"
  cat <<'LAUNCHER'
blackbird_release=$(CDPATH= cd -- "$blackbird_install_home/current" && pwd -P)
BLACKBIRD_SPRITE_ASSET=${BLACKBIRD_SPRITE_ASSET:-"$blackbird_release/share/blackbird/assets/sr71.png"}
export BLACKBIRD_SPRITE_ASSET
exec "$blackbird_release/scripts/blackbird" "$@"
LAUNCHER
} > "$blackbird_launcher"
chmod 755 "$blackbird_launcher"

if [ -f "$blackbird_prefix/bin/blackbird" ]; then
  blackbird_previous_launcher=$(mktemp "$blackbird_prefix/bin/.blackbird-previous-XXXXXXXX")
  cp -p -- "$blackbird_prefix/bin/blackbird" "$blackbird_previous_launcher"
fi
blackbird_launcher_published=true
mv -f -- "$blackbird_launcher" "$blackbird_prefix/bin/blackbird"
blackbird_launcher=''

blackbird_link=$blackbird_home/.current-$$
ln -s -- "$blackbird_generation" "$blackbird_link"
blackbird_replace_symlink "$blackbird_link" "$blackbird_home/current"
blackbird_link=''
blackbird_activated=true

printf 'Installed Blackbird: %s/bin/blackbird\nRelease: %s (%s)\nVersion: %s\nGeneration: %s\n' \
  "$blackbird_prefix" "$blackbird_resolved_version" "$blackbird_target" "$blackbird_bin_version" "$blackbird_generation"
case ":${PATH:-}:" in
  *":$blackbird_prefix/bin:"*) ;;
  *) printf 'Add %s/bin to PATH to invoke blackbird directly.\n' "$blackbird_prefix" ;;
esac
