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
      buildable = {
        aarch64-darwin = [ "aarch64-apple-darwin" ];
        aarch64-linux = lib.filter (lib.hasInfix "-linux-") targets;
        x86_64-linux = lib.filter (lib.hasInfix "-linux-") targets;
      };
      testable = {
        aarch64-darwin = [ "aarch64-apple-darwin" ];
        aarch64-linux = [ "aarch64-linux-gnu" "aarch64-linux-musl" ];
        x86_64-linux = [ "x86_64-linux-gnu" "x86_64-linux-musl" ];
      };
      forAllSystems = f: lib.mapAttrs (system: _: f system nixpkgs.legacyPackages.${system}) buildable;
      named = prefix: f: list: lib.listToAttrs (map (target: lib.nameValuePair "${prefix}-${target}" (f target)) list);
      erlLibs = beam: "${beam.hex}/lib/erlang/lib";
    in
    {
      packages = forAllSystems (
        system: pkgs:
        let
          nif = pkgs.callPackage ./nix/nif.nix { inherit (pkgs.beam_minimal.packages.erlang_27) erlang; };
          beam = pkgs.beam_minimal.packages.erlang_29;
          beamFor =
            target:
            if lib.hasSuffix "-musl" target then
              beam.overrideScope (_: _: { inherit (pkgs.pkgsMusl.beam_minimal.packages.erlang_29) erlang; })
            else
              beam;
          test =
            target:
            let
              beam = beamFor target;
            in
            pkgs.writeShellApplication {
              name = "test-${target}";
              text = builtins.readFile ./nix/test.sh;
              runtimeInputs = [ beam.erlang beam.elixir_1_20 pkgs.coreutils ];
              runtimeEnv = {
                ERL_LIBS = erlLibs beam;
                NIF = "${nif.nif target}";
              };
            };
        in
        {
          default = nif.nif (builtins.head testable.${system});
          inputs = pkgs.linkFarm "inputs" { inherit nixpkgs; };
          archives = pkgs.symlinkJoin {
            name = "pdfium-nif-archives";
            paths = map nif.archive buildable.${system};
          };
          release = pkgs.writeShellApplication {
            name = "release";
            text = builtins.readFile ./nix/release.sh;
            runtimeInputs = [ beam.erlang beam.elixir_1_20 pkgs.gh pkgs.git ];
            runtimeEnv = {
              ERL_LIBS = erlLibs beam;
              VERSION = nif.version;
            };
          };
          update = pkgs.writeShellApplication {
            name = "update";
            text = builtins.readFile ./nix/update.sh;
            runtimeInputs = [ pkgs.gh pkgs.git pkgs.gnused pkgs.jq ];
            runtimeEnv = {
              VERSION = nif.version;
              LIBPDFIUM = nif.libpdfiumTag;
              TARGETS = lib.concatStringsSep " " targets;
            };
          };
        }
        // named "nif" nif.nif buildable.${system}
        // named "archive" nif.archive buildable.${system}
        // named "libpdfium" nif.libpdfium targets
        // named "test" test testable.${system}
      );

      devShells = forAllSystems (
        system: pkgs:
        let
          beam = pkgs.beam_minimal.packages.erlang_29;
        in
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
