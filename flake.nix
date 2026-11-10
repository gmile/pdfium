{
  description = "Elixir interface for pdfium";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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
              mixEnv = "test";
              hash = "sha256-jcdjDCr7qRq8CgRx7OWiN8VdEJXFgkcOLYt9xW0roUQ=";
            };
            nif = pkgs.callPackage ./nix/nif.nix {
              inherit (pkgs.beam_minimal.packages.erlang_27) erlang;
              native = host;
              fine = "${deps}/fine";
              binaries = lib.importJSON ./libpdfium.json;
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
      mixFiles = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          ./mix.exs
          ./mix.lock
          ./VERSION
          ./libpdfium.json
        ];
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
          archives = pkgs.symlinkJoin {
            name = "pdfium-nif-archives";
            paths = map nif.archive buildable;
          };
          release = pkgs.writeShellApplication {
            name = "release";
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
              VERSION = nif.version;
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
              VERSION = nif.version;
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
              target ? host,
              files ? [
                ./mix.exs
                ./mix.lock
                ./lib
                ./test
              ],
              command,
            }:
            let
              beam = beamFor target;
            in
            pkgs.stdenvNoCC.mkDerivation {
              inherit name;
              src = lib.fileset.toSource {
                root = ./.;
                fileset = lib.fileset.unions files;
              };
              nativeBuildInputs = [
                beam.erlang
                beam.elixir_1_20
                beam.hex
              ];
              MIX_ENV = "test";
              HEX_OFFLINE = 1;
              buildPhase = ''
                export HOME=$TMPDIR MIX_DEPS_PATH=$PWD/deps
                echo 0.0.0 > VERSION
                echo '{"tag": "none"}' > libpdfium.json
                cp --recursive --no-preserve=mode ${deps} deps
                mix deps.compile --no-deps-check
                mkdir priv
                install --mode 755 ${nif.nif target}/* priv
                ${command}
              '';
              installPhase = "touch $out";
            };
          test =
            target:
            mix {
              name = "test-${target}";
              inherit target;
              command = "mix test --no-deps-check";
            };
          plt = mix {
            name = "plt";
            files = [
              ./mix.exs
              ./mix.lock
            ];
            command = ''
              mix dialyzer --plt
              mkdir $out
              cp _build/plts/*.plt $out
            '';
          };
          dialyzer = mix {
            name = "dialyzer";
            command = ''
              mkdir -p _build/plts
              cp ${plt}/* _build/plts
              mix dialyzer --no-check
            '';
          };
        in
        named "test" test testable
        // {
          inherit dialyzer;
        }
      );

      devShells = forAllSystems (
        { pkgs, beam, ... }:
        {
          default = pkgs.mkShell {
            packages = [
              beam.erlang
              beam.elixir_1_20
              beam.hex
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
