{
  description = "pdfium development environment (Erlang/OTP 29 + Elixir 1.20)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    dagger.url = "github:dagger/nix";
    dagger.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, dagger }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system (import nixpkgs { inherit system; }));
    in
    {
      devShells = forAllSystems (
        system: pkgs:
        let
          beam = pkgs.beam.packages.erlang_29;
          elixir = beam.elixir_1_20;
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              beam.erlang
              elixir
              pkgs.fish
              dagger.packages.${system}.dagger
              pkgs.gh
              pkgs.zig
            ];

            shellHook = ''
              case $- in *i*) exec ${pkgs.fish}/bin/fish ;; esac
            '';
          };
        }
      );
    };
}
