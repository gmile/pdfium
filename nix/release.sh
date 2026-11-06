gh release create "v$VERSION" --target "$(git rev-parse HEAD)" --title "v$VERSION" "$1"/*
mix deps.get
mix elixir_make.checksum --all
mix hex.publish package --yes
