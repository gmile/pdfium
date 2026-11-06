mkdir -p priv
install --mode 755 "$NIF"/* priv
mix deps.get
mix test
