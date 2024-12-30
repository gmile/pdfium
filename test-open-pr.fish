#!/usr/bin/env fish

git checkout main
git pull origin main
git push origin main
set value (date +%s)
git checkout -b branch-$value
echo "New value: $value\n" >> README.md
echo -n (awk 'BEGIN{FS=OFS="."} {$NF+=1}1' VERSION) > VERSION;
git add README.md VERSION
git commit -m "Testing $value"
git push origin branch-$value
gh pr create --fill
# gh pr merge branch-$value --auto --delete-branch --rebase
