# The published GitHub release tarball, unmodified: `nix run .#blackbird-bin`.
# Bump `version` and the two hashes together (hashes come from SHA256SUMS.txt:
# `nix hash convert --hash-algo sha256 --to sri HEX`).
{
  lib,
  stdenv,
  fetchurl,
  patchelf,
}:
let
  version = "0.8.0";
  sources = {
    aarch64-darwin = {
      target = "darwin-arm64";
      hash = "sha256-VU99B9KZLUeNfL54JYfWTV24UMzARGozaAofeaOEIok=";
    };
    x86_64-linux = {
      target = "linux-x86_64";
      hash = "sha256-ydSs/fnJJCKCwT9dwbXA2F4a1Y87NDXyq5pIOSxWTVI=";
    };
  };
  system = stdenv.hostPlatform.system;
  source =
    sources.${system}
      or (throw "blackbird-bin: no prebuilt release for ${system}; use the source build (`nix build`)");
  dist = "blackbird-v${version}-${source.target}";
in
stdenv.mkDerivation {
  pname = "blackbird-bin";
  inherit version;

  src = fetchurl {
    url = "https://github.com/antimemeai/blackbird/releases/download/v${version}/${dist}.tar.gz";
    inherit (source) hash;
  };
  sourceRoot = dist;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ patchelf ];

  # Keep the bundled LLVM libc++ / OpenSSL / Lua libraries and the
  # $ORIGIN/../lib RPATH exactly as released; only the ELF interpreter moves.
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    home="$out/lib/blackbird"
    mkdir -p "$home" "$out/bin"
    cp -a bin scripts share MANIFEST "$home/"
    if [ -d lib ]; then cp -a lib "$home/"; fi
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      interp="$(cat "$NIX_CC/nix-support/dynamic-linker")"
      for binfile in "$home/bin/"*; do
        if [ -f "$binfile" ] && [ -x "$binfile" ]; then
          patchelf --set-interpreter "$interp" "$binfile"
        fi
      done
    ''}
    cat > "$out/bin/blackbird" <<EOF
    #!/bin/sh
    set -eu
    export BLACKBIRD_SPRITE_ASSET="\''${BLACKBIRD_SPRITE_ASSET:-$home/share/blackbird/assets/sr71.png}"
    exec "$home/scripts/blackbird" "\$@"
    EOF
    chmod 755 "$out/bin/blackbird"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/blackbird" --version | grep -q '^blackbird '
    test -f "$out/lib/blackbird/share/blackbird/programs/turn.lua"
    runHook postInstallCheck
  '';

  meta = {
    description = "Blackbird prebuilt release binaries";
    homepage = "https://github.com/antimemeai/blackbird";
    changelog = "https://github.com/antimemeai/blackbird/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "blackbird";
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
