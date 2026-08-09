{
  description = "pdfium development environment (Erlang/OTP 29 + Elixir 1.20)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in
    {
      devShells = forAllSystems (
        pkgs:
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
              # custom/build-for-mac.sh reads builds.json and fetches OTP,
              # libpdfium and the Fine headers with these. The shell brings no
              # compiler of its own: the script builds against the OTP headers it
              # downloads and the macOS SDK, and a wrapped cc puts link flags on
              # the compile step, which its -Werror will not have.
              pkgs.jq
              pkgs.wget
              pkgs.git
            ];

            shellHook = ''
              case $- in *i*) exec ${pkgs.fish}/bin/fish ;; esac
            '';
          };
        }
      );
    };
}
