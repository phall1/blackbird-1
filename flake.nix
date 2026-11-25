{
  description = "Blackbird — native C++23 + Lua 5.5.1 coding harness and sovereign multi-agent Command Post";

  # Opt-in. Nothing in the repository requires Nix; this is one of three
  # equivalent entry points (Nix, mise, plain CMake). See README.md.
  #
  #   nix run   github:antimemeai/blackbird        # try it, no checkout
  #   nix build                                     # ./result/bin/blackbird from this checkout
  #   nix develop                                   # pinned toolchain shell (or `direnv allow`)
  #   nix run .#blackbird-bin                       # the published release tarball

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # LLVM 23 with libc++ on every host, matching the project's compiler
      # profiles (macos-llvm23 / linux-llvm23).
      toolchainFor = pkgs: rec {
        llvm = pkgs.llvmPackages_23;
        stdenv = llvm.libcxxStdenv;
        buildTools = [
          pkgs.cmake
          pkgs.ninja
          pkgs.python3
          pkgs.cargo
          pkgs.rustc
        ];
        libs = [
          pkgs.lua5_5
          pkgs.openssl
        ];
      };
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          inherit (pkgs) lib;
          tc = toolchainFor pkgs;
          shortRev = self.shortRev or self.dirtyShortRev or "unknown";
          blackbird-bin = pkgs.callPackage ./packaging/nix/blackbird-bin.nix { };
        in
        {
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.blackbird;

          # Built from this source tree — the same layout scripts/install-blackbird
          # produces under ~/.local/lib/blackbird/current.
          blackbird = tc.stdenv.mkDerivation (finalAttrs: {
            pname = "blackbird";
            version = "0-unstable-${shortRev}";

            src = lib.fileset.toSource {
              root = ./.;
              fileset = lib.fileset.unions [
                ./CMakeLists.txt
                ./CMakePresets.json
                ./src
                ./include
                ./tests
                ./programs
                ./profiles
                ./assets
                ./scripts
                ./tooling
                ./third_party
                ./crates
              ];
            };

            cargoDeps = pkgs.rustPlatform.importCargoLock {
              lockFile = ./crates/blackbird-p2p/Cargo.lock;
            };
            cargoRoot = "crates/blackbird-p2p";

            nativeBuildInputs = tc.buildTools ++ [ pkgs.rustPlatform.cargoSetupHook ];
            buildInputs = tc.libs;

            # The tree carries no .git, so CMake cannot ask Git for the commit.
            postPatch = ''
              substituteInPlace CMakeLists.txt \
                --replace-fail 'set(BLACKBIRD_GIT_COMMIT "unknown")' \
                               'set(BLACKBIRD_GIT_COMMIT "${shortRev}")'
            '';

            resourceRoot = "${placeholder "out"}/lib/blackbird/share/blackbird";
            cmakeFlags = [
              "-DCMAKE_BUILD_TYPE=Release"
              "-DBLACKBIRD_DEBUG=OFF"
              "-DBLACKBIRD_INSTRUMENTATION=none"
              "-DBLACKBIRD_ENABLE_IROH=on"
              # Store paths are the dependency closure; no need to vendor static archives.
              "-DBLACKBIRD_STATIC_OPENSSL=off"
              "-DBLACKBIRD_STATIC_LUA=off"
              # Pin dependencies explicitly: Darwin builds are unsandboxed, and the
              # project's CMake otherwise prefers Homebrew's OpenSSL when present.
              "-DOPENSSL_ROOT_DIR=${lib.getDev pkgs.openssl};${lib.getLib pkgs.openssl}"
              "-DLUA_INCLUDE_DIR=${pkgs.lua5_5}/include"
              "-DLUA_LIBRARY=${lib.getLib pkgs.lua5_5}/lib/liblua${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}"
              "-DBLACKBIRD_RESOURCE_ROOT=${finalAttrs.resourceRoot}"
            ];

            ninjaFlags = [
              "blackbird"
              "blackbird-candidate"
              "blackbird-auth"
              "blackbird-workflow"
              "blackbird-colleague"
              "blackbird-resource-sampler"
              "blackbird-raw-reader"
              "blackbird-token-usage"
            ];

            # The full suite is the project's rigor gate (scripts/rigor check);
            # the install check below is the same offline smoke the installer runs.
            doCheck = false;

            installPhase = ''
              runHook preInstall
              home="$out/lib/blackbird"
              mkdir -p "$home/bin" "$home/scripts" "$resourceRoot" "$out/bin"
              for tool in blackbird blackbird-candidate blackbird-auth blackbird-workflow \
                          blackbird-colleague blackbird-job-runner blackbird-archive \
                          blackbird-resource-sampler blackbird-raw-reader blackbird-token-usage; do
                install -m755 "$tool" "$home/bin/$tool"
              done
              cp -R "$src/programs" "$src/assets" "$src/profiles" "$resourceRoot/"
              install -m755 "$src/scripts/blackbird" "$home/scripts/blackbird"
              cat > "$out/bin/blackbird" <<EOF
              #!/bin/sh
              set -eu
              export BLACKBIRD_SPRITE_ASSET="\''${BLACKBIRD_SPRITE_ASSET:-$resourceRoot/assets/sr71.png}"
              exec "$home/scripts/blackbird" "\$@"
              EOF
              chmod 755 "$out/bin/blackbird"
              runHook postInstall
            '';

            doInstallCheck = true;
            installCheckPhase = ''
              runHook preInstallCheck
              export HOME="$TMPDIR/home" BLACKBIRD_AUTH_HOME="$TMPDIR/auth"
              mkdir -p "$HOME"
              # Capture to files: `cmd | grep -q` trips pipefail with SIGPIPE.
              "$out/bin/blackbird" --version > "$TMPDIR/version"
              grep '^blackbird ${shortRev} ' "$TMPDIR/version"
              "$out/bin/blackbird" --help >/dev/null
              "$out/bin/blackbird" auth providers >/dev/null
              cat > "$TMPDIR/smoke.lua" <<'LUA'
              local result = blackbird.call('exec', {argv={'/bin/sh', '-c', 'exit 0'}, pty=true})
              assert(result.exit_code == 0, 'PTY helper failed')
              print('BLACKBIRD_INSTALL_SMOKE')
              LUA
              "$out/bin/blackbird" --plain --session "$TMPDIR/session" \
                --workflow "$TMPDIR/smoke.lua" --once offline-install-smoke > "$TMPDIR/smoke.out"
              grep -q BLACKBIRD_INSTALL_SMOKE "$TMPDIR/smoke.out"
              runHook postInstallCheck
            '';

            meta = {
              description = "Native C++23 + Lua 5.5.1 coding harness and sovereign multi-agent Command Post";
              homepage = "https://github.com/antimemeai/blackbird";
              license = lib.licenses.mit;
              mainProgram = "blackbird";
              platforms = systems;
            };
          });
        }
        # The published release tarball, on hosts that have one.
        // lib.optionalAttrs (lib.meta.availableOn pkgs.stdenv.hostPlatform blackbird-bin) {
          inherit blackbird-bin;
        }
      );

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = nixpkgs.lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.blackbird;
        };
      });

      devShells = forAllSystems (
        pkgs:
        let
          tc = toolchainFor pkgs;
        in
        {
          # Everything `cmake --preset dev` and `scripts/install-blackbird` need.
          default = pkgs.mkShell.override { inherit (tc) stdenv; } {
            packages =
              tc.buildTools
              ++ tc.libs
              ++ [
                tc.llvm.clang-tools # clangd, clang-format, clang-tidy
                pkgs.lua-language-server
                pkgs.stylua
              ];
            # The project's CMake picks CC/CXX up from the environment.
            shellHook = ''
              export CC=${tc.stdenv.cc}/bin/clang CXX=${tc.stdenv.cc}/bin/clang++
              export OPENSSL_ROOT_DIR=${pkgs.lib.getDev pkgs.openssl}:${pkgs.lib.getLib pkgs.openssl}
              export LUA_DIR=${pkgs.lua5_5}
            '';
          };
        }
      );

      checks = forAllSystems (pkgs: {
        inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) blackbird;
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
