{
  lib,
  pkgs,
  erlang,
  fetchzip,
  native,
  fine,
  binaries,
  version,
}:

let
  libpdfiumTag = binaries.tag;

  darwin = target: lib.hasSuffix "-apple-darwin" target;
  musl = target: lib.hasSuffix "-musl" target;
  arch =
    target:
    {
      aarch64 = "arm64";
      x86_64 = "x64";
    }
    .${builtins.head (lib.splitString "-" target)};
  library = target: if darwin target then "libpdfium.dylib" else "libpdfium.so";

  libpdfium =
    target:
    fetchzip {
      url = "https://github.com/bblanchon/pdfium-binaries/releases/download/${
        lib.replaceStrings [ "/" ] [ "%2F" ] libpdfiumTag
      }/pdfium-${
        if darwin target then "mac" else "linux"
      }${lib.optionalString (musl target) "-musl"}-${arch target}.tgz";
      hash = binaries.hashes.${target} or lib.fakeHash;
      stripRoot = false;
    };

  cross = {
    aarch64-linux-gnu = "aarch64-multiplatform";
    aarch64-linux-musl = "aarch64-multiplatform-musl";
    x86_64-linux-gnu = "gnu64";
    x86_64-linux-musl = "musl64";
  };

  stdenvFor =
    target: if target == native then pkgs.stdenv else pkgs.pkgsCross.${cross.${target}}.stdenv;

  nif =
    target:
    (stdenvFor target).mkDerivation {
      name = "pdfium-nif-${target}";
      src = lib.fileset.toSource {
        root = ../.;
        fileset = lib.fileset.unions [
          ../Makefile
          ../c_src
        ];
      };
      makeFlags = [
        "PREFIX=${placeholder "out"}"
        "OS=${if darwin target then "mac" else "linux"}"
        "PDFIUM=${libpdfium target}"
        "ERTS_INCLUDE_DIR=${erlang}/lib/erlang/usr/include"
        "FINE_INCLUDE_DIR=${fine}/c_include"
      ];
      dontInstall = true;
      dontFixup = true;
    };

  archive =
    target:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "pdfium-nif-archive-${target}";
      inherit version;
      nativeBuildInputs = [ erlang ];
      dontUnpack = true;
      buildPhase = ''
        nif_version=$(erl -noshell -eval 'io:format(erlang:system_info(nif_version)), halt().')
        mkdir -p $out
        tar --create --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
          --directory ${nif target} pdfium_nif.so ${library target} \
          | gzip --no-name > "$out/pdfium-nif-$nif_version-${target}-${version}.tar.gz"
      '';
      dontInstall = true;
    };
in
{
  inherit
    nif
    archive
    libpdfium
    version
    libpdfiumTag
    ;
}
