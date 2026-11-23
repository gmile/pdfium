{
  description = "Elixir interface for pdfium";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      targets = [
        "aarch64-linux-gnu"
        "aarch64-linux-musl"
        "x86_64-linux-gnu"
        "x86_64-linux-musl"
        "aarch64-apple-darwin"
      ];
      linux = lib.filter (lib.hasInfix "-linux-") targets;
      buildable = {
        aarch64-darwin = [ "aarch64-apple-darwin" ];
        aarch64-linux = linux;
        x86_64-linux = linux;
      };
      forAllSystems =
        f:
        lib.mapAttrs (
          system: buildable:
          let
            pkgs = nixpkgs.legacyPackages.${system};
            testable = lib.filter (lib.hasPrefix "${lib.head (lib.splitString "-" system)}-") buildable;
            host = lib.head testable;
            beam = pkgs.beam_minimal.packages.erlang_29;
            deps = beam.fetchMixDeps {
              pname = "pdfium-deps";
              version = "locked";
              src = mixFiles;
              mixEnv = "";
              hash = "sha256-gsXPt5NJt7ViOtI0MpJVcpLBOIahq4VuTiaqQfm1TDI=";
            };
            nif = pkgs.callPackage ./nix/nif.nix {
              inherit (pkgs.beam_minimal.packages.erlang_27) erlang;
              native = host;
              fine = "${deps}/fine";
              binaries = lib.importJSON ./libpdfium.json;
              inherit version;
            };
          in
          f {
            inherit
              pkgs
              buildable
              testable
              host
              beam
              deps
              nif
              ;
          }
        ) buildable;
      mixTools = beam: [
        beam.erlang
        beam.elixir_1_20
        beam.hex
      ];
      mixFiles = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          ./mix.exs
          ./mix.lock
          ./VERSION
          ./libpdfium.json
        ];
      };
      version = lib.trim (builtins.readFile ./VERSION);
      next =
        let
          bumped = part: toString (lib.toInt (part version) + 1);
        in
        {
          major = "${bumped lib.versions.major}.0.0";
          minor = "${lib.versions.major version}.${bumped lib.versions.minor}.0";
          patch = "${lib.versions.majorMinor version}.${bumped lib.versions.patch}";
        };
      named =
        prefix: f: list:
        lib.listToAttrs (map (target: lib.nameValuePair "${prefix}-${target}" (f target)) list);
    in
    {
      packages = forAllSystems (
        {
          pkgs,
          beam,
          nif,
          buildable,
          host,
          ...
        }:
        {
          default = nif.nif host;
          release = pkgs.writeShellApplication {
            name = "release";
            runtimeInputs = [
              pkgs.gawk
              pkgs.git
              pkgs.gnused
            ];
            runtimeEnv = next;
            text = ''
              case ''${1:-} in
                major | minor | patch) version=''${!1} ;;
                *) echo "usage: release major|minor|patch" >&2 && exit 1 ;;
              esac
              git fetch --quiet origin main
              if [ "$(git branch --show-current)" != main ] ||
                [ -n "$(git status --porcelain --untracked-files=no)" ] ||
                [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
                echo "release from a clean main that matches origin/main" >&2
                exit 1
              fi
              awk '/^## \[Unreleased\]/ { open = 1; next } /^## / { exit } open && NF { found = 1 } END { exit !found }' CHANGELOG.md ||
                { echo "CHANGELOG.md has nothing under [Unreleased]" >&2 && exit 1; }
              sed --in-place "s/^## \[Unreleased\]$/## [Unreleased]\n\n## [v$version] - $(date --utc +%F)/" CHANGELOG.md
              echo "$version" > VERSION
              git commit --quiet VERSION CHANGELOG.md --message "Release v$version"
              git push origin main
            '';
          };
          archives = pkgs.symlinkJoin {
            name = "pdfium-nif-archives";
            paths = map nif.archive buildable;
          };
          publish = pkgs.writeShellApplication {
            name = "publish";
            text = ''
              grep --fixed-strings --quiet "## [v$VERSION]" CHANGELOG.md
              mix deps.get
              mix hex.audit
              gh release create "v$VERSION" --target "$(git rev-parse HEAD)" --generate-notes "$1"/*
              mix elixir_make.checksum --all
              mix hex.publish --yes
            '';
            runtimeInputs = [
              beam.erlang
              beam.elixir_1_20
              pkgs.gh
              pkgs.git
            ];
            runtimeEnv = {
              ERL_LIBS = "${beam.hex}/lib/erlang/lib";
              VERSION = version;
            };
          };
          update = pkgs.writeShellApplication {
            name = "update";
            text = builtins.readFile ./nix/update.sh;
            excludeShellChecks = [ "SC2016" ];
            runtimeInputs = [
              pkgs.gh
              pkgs.git
              pkgs.gnused
              pkgs.jq
            ];
            runtimeEnv = {
              LIBPDFIUM = nif.libpdfiumTag;
              TARGETS = lib.concatStringsSep " " targets;
            };
          };
        }
        // named "nif" nif.nif buildable
        // named "archive" nif.archive buildable
        // named "libpdfium" nif.libpdfium targets
      );

      checks = forAllSystems (
        {
          pkgs,
          beam,
          deps,
          nif,
          testable,
          host,
          ...
        }:
        let
          trimmed =
            erlang:
            erlang.overrideAttrs (old: {
              installTargets = [ "install" ];
              configureFlags =
                old.configureFlags
                ++ map (app: "--without-${app}") [
                  "common_test"
                  "debugger"
                  "diameter"
                  "eldap"
                  "et"
                  "ftp"
                  "jinterface"
                  "megaco"
                  "mnesia"
                  "observer"
                  "odbc"
                  "reltool"
                  "snmp"
                  "ssh"
                  "tftp"
                  "wx"
                ];
            });
          beamFor =
            target:
            if lib.hasSuffix "-musl" target then
              beam.overrideScope (
                _: _: { erlang = trimmed pkgs.pkgsMusl.beam_minimal.packages.erlang_29.erlang; }
              )
            else
              beam;
          mix =
            {
              name,
              env ? "test",
              target ? host,
              files ? [ ],
              setup ? ''
                cp --recursive --no-preserve=mode ${compiled.${env}}/. .
                mkdir priv
                install --mode 755 ${nif.nif target}/* priv
              '',
              command,
              output ? "touch $out",
            }:
            pkgs.stdenvNoCC.mkDerivation {
              inherit name;
              src = lib.fileset.toSource {
                root = ./.;
                fileset = lib.fileset.unions (
                  [
                    ./mix.exs
                    ./mix.lock
                  ]
                  ++ files
                );
              };
              nativeBuildInputs = mixTools (beamFor target);
              MIX_ENV = env;
              HEX_OFFLINE = 1;
              buildPhase = ''
                export HOME=$TMPDIR MIX_DEPS_PATH=$PWD/deps
                echo 0.0.0 > VERSION
                echo '{"tag": "none"}' > libpdfium.json
                ${setup}
              '';
              doCheck = true;
              checkPhase = ''
                runHook preCheck
                ${command}
                runHook postCheck
              '';
              installPhase = output;
            };
          compiled = lib.genAttrs [ "dev" "test" ] (
            env:
            mix {
              name = "deps-${env}";
              inherit env;
              setup = "cp --recursive --no-preserve=mode ${deps} deps";
              command = "mix deps.compile --no-deps-check";
              output = ''
                mkdir $out
                cp --recursive deps _build $out
              '';
            }
          );
          plt = mix {
            name = "plt";
            env = "dev";
            command = "mix dialyzer --plt";
            output = ''
              mkdir $out
              cp _build/plts/*.plt $out
            '';
          };
          test =
            target:
            mix {
              name = "test-${target}";
              inherit target;
              files = [
                ./.formatter.exs
                ./lib
                ./test
              ];
              command = ''
                mix format --check-formatted
                mix compile --warnings-as-errors
                mix deps.unlock --check-unused
                mix xref graph --format cycles --label compile-connected --fail-above 0
                mix test --warnings-as-errors
              '';
            };
        in
        named "test" test testable
        // {
          docs = mix {
            name = "docs";
            env = "dev";
            files = [
              ./lib
              ./README.md
              ./CHANGELOG.md
            ];
            command = "mix docs --warnings-as-errors";
          };
          dialyzer = mix {
            name = "dialyzer";
            env = "dev";
            files = [ ./lib ];
            command = ''
              mkdir _build/plts
              cp ${plt}/* _build/plts
              mix dialyzer --no-check
            '';
          };
          nixfmt =
            pkgs.runCommand "nixfmt"
              {
                nativeBuildInputs = [ pkgs.nixfmt ];
                src = lib.fileset.toSource {
                  root = ./.;
                  fileset = lib.fileset.fileFilter (file: file.hasExt "nix") ./.;
                };
              }
              ''
                find $src -name '*.nix' -exec nixfmt --check {} +
                touch $out
              '';
        }
      );

      formatter = forAllSystems ({ pkgs, ... }: pkgs.nixfmt-tree);

      devShells = forAllSystems (
        { pkgs, beam, ... }:
        {
          default = pkgs.mkShell {
            packages = mixTools beam ++ [
              pkgs.fish
              pkgs.gh
            ];

            shellHook = ''
              case $- in *i*) exec ${pkgs.fish}/bin/fish ;; esac
            '';
          };
        }
      );
    };
}
