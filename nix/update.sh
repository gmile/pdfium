tag=${1:-$(gh api repos/bblanchon/pdfium-binaries/releases/latest --jq .tag_name)}
if [ "$tag" = "$LIBPDFIUM" ]; then
  echo "Already at $tag"
  exit 0
fi
sed --in-place "s|@libpdfium \"$LIBPDFIUM\"|@libpdfium \"$tag\"|" mix.exs
{
  echo "{"
  for target in $TARGETS; do
    url=$(nix eval --json ".#libpdfium-$target.urls" | jq --raw-output '.[0]')
    echo "  \"$target\" = \"$(nix store prefetch-file --unpack --json "$url" | jq --raw-output .hash)\";"
  done
  echo "}"
} > nix/libpdfium.nix
git commit mix.exs nix/libpdfium.nix --message "Update libpdfium to $tag"
next="${VERSION%.*}.$(( ${VERSION##*.} + 1 ))"
sed --in-place "s/@version \"$VERSION\"/@version \"$next\"/" mix.exs
git commit mix.exs --message "Update package to version $next"
git push origin HEAD:refs/heads/update-libpdfium
gh pr create --base main --head update-libpdfium --reviewer gmile --fill-first
