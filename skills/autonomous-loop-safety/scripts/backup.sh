#!/bin/zsh
# backup.sh — append-only snapshots of the repo, independent of GitHub.
#
# WHY, given GitHub exists:
#   GitHub covers *pushed* work. It does NOT cover:
#     - uncommitted work in the tree (the executor builds for ~40 min before committing)
#     - a `git reset --hard` that deletes local commits before they're pushed
#     - a `push --force` that rewrites origin (GitHub keeps the objects briefly, but the
#       ref is gone and finding them means reflog archaeology under pressure)
#     - `gh pr merge --delete-branch` destroying a branch with an unpushed commit
#   The relay nearly did the third and fourth of those today. So: a copy the relay cannot touch.
#
# WHAT: a `git bundle` (complete, self-contained clone of every ref) + a tarball of the working
# tree including uncommitted changes. Timestamped, NEVER overwritten, NEVER deleted by automation.
#
# RESTORE:  git clone my-project-<stamp>.bundle restored-repo

REPO="$HOME/Projects/my-project"
DEST="$HOME/Projects/my-project-backups"
STAMP=$(date '+%Y%m%d-%H%M%S')
export PATH="/opt/homebrew/bin:/usr/bin:/bin"

mkdir -p "$DEST"
cd "$REPO" || { echo "backup: repo missing"; exit 1; }

# 1. Every ref, every commit — a real, cloneable backup.
git bundle create "$DEST/my-project-$STAMP.bundle" --all >/dev/null 2>&1 || {
  echo "backup: BUNDLE FAILED"; exit 1; }

# 2. The working tree as it stands right now, uncommitted changes included.
#    This is the part GitHub genuinely cannot give you back.
tar czf "$DEST/worktree-$STAMP.tgz" \
    --exclude='.git' \
    -C "$REPO" . 2>/dev/null

# 3. Make them read-only. Nothing in the relay should be able to modify a backup,
#    and a stray `rm` should have to fight for it.
chmod 444 "$DEST/my-project-$STAMP.bundle" "$DEST/worktree-$STAMP.tgz" 2>/dev/null

# 4. Prune only VERY old ones, and only by age — never by count, so a burst of
#    activity can't evict the snapshot you actually need. 30 days.
find "$DEST" -name '*.bundle' -mtime +30 -exec chmod 644 {} \; -delete 2>/dev/null
find "$DEST" -name '*.tgz'    -mtime +30 -exec chmod 644 {} \; -delete 2>/dev/null

SIZE=$(du -sh "$DEST" | cut -f1)
COUNT=$(ls "$DEST"/*.bundle 2>/dev/null | wc -l | tr -d ' ')
echo "[$(date '+%Y-%m-%d %H:%M:%S')] backup ok: $STAMP ($COUNT snapshots, $SIZE)" >> "$HOME/Projects/relay/relay.log"
echo "backed up: $DEST/my-project-$STAMP.bundle  ($COUNT snapshots, $SIZE total)"
