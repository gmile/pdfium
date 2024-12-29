#!/usr/bin/env fish

set date (date +%s)
git co -b branch-$date
echo branch-$date >> README.md 
git add README.md 
git commit -m "testing $date" 
gh pr create --fill
gh pr merge branch-$date --auto --delete-branch --rebase
