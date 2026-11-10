tag=${1:-$(gh api repos/bblanchon/pdfium-binaries/releases/latest --jq .tag_name)}
if [ "$tag" = "$LIBPDFIUM" ]; then
  echo "Already at $tag"
  exit 0
fi
jq --null-input --arg tag "$tag" '{$tag}' > libpdfium.json
hashes=$(
  for target in $TARGETS; do
    url=$(nix eval --raw ".#libpdfium-$target.urls" --apply builtins.head)
    nix store prefetch-file --unpack --json "$url" | jq --arg target "$target" '{($target): .hash}'
  done
)
jq --slurp --arg tag "$tag" '{$tag, hashes: add}' <<< "$hashes" > libpdfium.json
git commit libpdfium.json --message "Update libpdfium to $tag"
next="${VERSION%.*}.$(( ${VERSION##*.} + 1 ))"
echo "$next" > VERSION
git commit VERSION --message "Update package to version $next"
git push origin HEAD:refs/heads/update-libpdfium
gh pr create --base main --head update-libpdfium --reviewer gmile --fill-first
gh workflow run ci.yaml --ref update-libpdfium
