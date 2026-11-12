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
sed --in-place "s|^## \[Unreleased\]$|## [Unreleased]\n\n### Changed\n\n- Built against libpdfium $tag.|" CHANGELOG.md
git commit libpdfium.json CHANGELOG.md --message "Update libpdfium to $tag"
git push --force origin HEAD:refs/heads/update-libpdfium
if [ "$(gh pr list --head update-libpdfium --json number --jq length)" = 0 ]; then
  gh pr create --base main --head update-libpdfium --reviewer gmile --fill-first
else
  gh pr edit update-libpdfium --title "Update libpdfium to $tag"
fi
gh workflow run ci.yaml --ref update-libpdfium
