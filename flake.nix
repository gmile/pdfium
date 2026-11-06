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
    in
    {
      packages = forAllSystems (
        system: pkgs:
        let
          nif = pkgs.callPackage ./nix/nif.nix { inherit (pkgs.beam_minimal.packages.erlang_29) erlang; };
        in
        {
          default = nif.nif (builtins.head testable.${system});
          inputs = pkgs.linkFarm "inputs" { inherit nixpkgs; };
          archives = pkgs.symlinkJoin {
            name = "pdfium-nif-archives";
            paths = map nif.archive buildable.${system};
          };
        }
        // named "nif" nif.nif buildable.${system}
        // named "archive" nif.archive buildable.${system}
        // named "libpdfium" nif.libpdfium targets
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
