# Goal 3: Staying in Sync & Undoing Mistakes

**Workbook:** Git for Data Engineers (Workbook 00)
**Prerequisites:** Goals 1 and 2 complete — `de-git-sandbox` repo exists on `main`, with a resolved merge under its belt and a proper `.gitignore`

---

## What this goal covers

Pulling and fetching without clobbering your own work · the three ways to undo something (`reset`, `revert`, `checkout`) and when each is the right — or dangerous — choice · Git LFS for the oversized files real pipelines eventually produce

This is the goal that matters most under pressure. Merge conflicts are annoying; a bad `reset --hard` can genuinely lose work. Every step here is designed so you feel the difference between "safe to run" and "read twice before you run this."

---

## 3.1 — Pull, Fetch, and Staying in Sync

**Step 1 — Understand the difference before you touch either command**

`git fetch` downloads what's changed on the remote but does **not** touch your working files. `git pull` is `fetch` + `merge` in one step — it *does* touch your working files. When you're not sure what's changed upstream, fetch first, look, then decide.

```bash
cd de-git-sandbox
git fetch origin
git log --oneline main..origin/main
```

That second command shows commits that exist on the remote but not yet in your local `main`. If it's empty, you're already in sync.

**Step 2 — Simulate an upstream change**

To see this in action, you need a commit to exist on GitHub that your local clone doesn't have yet. The simplest way: edit the file directly on GitHub's website.

1. Go to your `de-git-sandbox` repo on GitHub.
2. Click into `load.py`.
3. Click the pencil icon (**Edit this file**) in the top right.
4. Add a line, e.g. `# reviewed by team`, anywhere in the file.
5. Scroll down to **Commit changes** — select **Commit directly to the `main` branch**, then click **Commit changes**.

That commit now exists on GitHub but not in the clone on your machine. Back in your terminal:

```bash
git fetch origin
git log --oneline main..origin/main
# shows the new commit you just made on GitHub
```

**Step 3 — Pull it in**

This is the step that actually brings the change down from GitHub into your local files — everything before this was just looking, not fetching content.

```bash
git pull origin main
```

Since nobody else changed anything locally in the meantime, git can just copy the new commit straight in — no merging or decision-making needed, because your local `main` and GitHub's `main` were only different by "GitHub has one extra commit you don't have yet." (Git calls this a **fast-forward**: your local branch pointer simply moves forward to match GitHub's, nothing to reconcile.)

You should see output like:

```
Updating a1b2c3d..e4f5g6h
Fast-forward
 load.py | 1 +
 1 file changed, 1 insertion(+)
```

Confirm the change actually landed in your files:

```bash
git log --oneline -5
cat load.py
```

`load.py` should now contain the `# reviewed by team` line you added on GitHub in Step 2.

> **Troubleshooting — "You have divergent branches and need to specify how to reconcile them"**
> This means git found commits on *both* sides that the other doesn't have — not the simple "GitHub has one extra commit" case above. Newer versions of git (2.27+) won't guess how to combine them, so you have to tell it once. Since this workbook uses regular merges throughout (not rebase), set that as your default:
> ```bash
> git config pull.rebase false
> git pull origin main
> ```
> If this opens a real merge (rather than fast-forwarding cleanly), resolve it the same way you did in Goal 2 — read the conflict markers, edit by hand, `git add`, then commit.
> Use `git config --global pull.rebase false` instead if you want this set once for every repo on your machine, not just this one.

> **Troubleshooting — "Your local changes to the following files would be overwritten by merge"**
> Git is protecting you here, not blocking you arbitrarily. You have uncommitted local edits that collide with the incoming pull. Either commit your changes first (`git add . && git commit -m "..."`) or stash them (`git stash`) before pulling, then reapply with `git stash pop`.

**A note on `--rebase` (not something to run right now)**

You're already in sync after Step 3 — there's nothing left to pull, so running another pull command here would just say `Already up to date` and teach you nothing. This is worth knowing conceptually for *next time* you pull, though:

```bash
git pull --rebase origin main
```

Plain `git pull` (what you did in Step 3) merges — it creates a merge commit that ties your local history and the incoming history together. `git pull --rebase` instead replays your local commits on top of the latest upstream, keeping history in a straight line with no merge commit at all.

**When to reach for which:**
- Plain `git pull` (merge) — fine as a default, and what this workbook uses throughout.
- `git pull --rebase` — nicer history on a solo branch only you push to. Avoid it on a shared branch where others may have already pulled your commits, since rebase rewrites commit hashes and can create a mess for anyone who already has the old ones.

Nothing to run here — just something to recognize the next time `git pull` prompts you about `pull.rebase`.

---

## 3.2 — Undoing Mistakes: Reset, Revert, and Checkout

These three get confused constantly because they sound similar and do very different things. The rule of thumb: **if the mistake is already pushed and others may have pulled it, use `revert`. If it's still local and only yours, `reset` is fine.**

**Step 1 — `git checkout` for restoring a single file**

Make a bad edit on purpose:

```bash
echo "this is a mistake" >> config.yaml
git status
```

Undo it before staging:

```bash
git checkout -- config.yaml
cat config.yaml
# the mistake is gone, file matches last commit
```

This only works for uncommitted changes. Once something's committed, `checkout` on a file won't undo it the same way — you need `reset` or `revert`.

**Step 2 — `git reset` for rewinding local commits (use with care)**

Make a throwaway commit to practice on:

```bash
echo "temp note" >> config.yaml
git add config.yaml
git commit -m "temp note - to be undone"
```

**Soft reset** — undo the commit, keep the changes staged:

```bash
git reset --soft HEAD~1
git status
# changes are back in the staging area, nothing lost
```

**Mixed reset** (the default) — undo the commit *and* unstage, but keep the file changes:

```bash
git commit -m "temp note - to be undone (again)"
git reset HEAD~1
git status
# changes exist in the file, but unstaged
```

**Hard reset** — undo the commit and discard the changes entirely:

```bash
git commit -m "temp note - to be undone (again, again)"
git reset --hard HEAD~1
git status
cat config.yaml
# the temp note is completely gone
```

> **This is the command that loses work if used carelessly.** `--hard` discards uncommitted and committed-but-reset changes with no confirmation prompt. Never run `git reset --hard` without first checking `git status` and `git log` to be sure what you're about to discard.

**Step 3 — `git revert` for undoing something already shared**

Reset rewrites history — fine on a solo local branch, dangerous once you've pushed and someone else might have pulled those commits. `revert` is the safe equivalent for shared history: it adds a *new* commit that undoes a previous one, without erasing anything.

```bash
git log --oneline -5
```

Find the commit you want to undo in that output — each line starts with a short hash like `a3f9c21`. For this exercise, use the `load.py` commit you pulled in from GitHub back in 3.1 (the "reviewed by team" one) — it's a clean, single-line change with nothing later depending on it, so revert works with no surprises. `abc1234` below is a placeholder; replace it with that commit's actual hash from your own `git log` output.

```bash
git revert abc1234
```

> **Avoid reverting the `.env` commits from Goal 2 for this exercise.** That file was added in one commit and then untracked in a later one (`git rm --cached`), so reverting the add now collides with the later removal — git reports `CONFLICT (modify/delete)` because it genuinely can't tell which side should win. This isn't broken; it's a legitimately tangled history, just not the case this exercise is meant to demonstrate. If you hit it, run `git revert --abort` to back out cleanly and pick a simpler commit instead.

Git opens an editor for the revert commit message — save and close it. Check:

```bash
git log --oneline -5
```

You'll see the original commit still there, plus a new commit undoing it. History is preserved, nothing is rewritten.

> **Rule of thumb:** if you've already run `git push` and the commit might exist on someone else's machine, use `revert`, not `reset --hard` followed by a force push. Rewriting shared history is one of the most common ways git relationships between collaborators break.

---

## 3.3 — Git LFS for Oversized Files

Regular git tracks every version of every file forever, in full. That's fine for code, terrible for a 500MB CSV — your repo balloons and clone times crawl. Git LFS (Large File Storage) stores big files outside the normal git history and keeps only a lightweight pointer in it.

**Step 1 — Install Git LFS**

```bash
# macOS
brew install git-lfs

# Ubuntu/Debian
sudo apt install git-lfs

git lfs install
```

**Step 2 — Simulate an oversized file**

```bash
python3 -c "
import csv
with open('large_sample.csv', 'w') as f:
    w = csv.writer(f)
    w.writerow(['id', 'value'])
    for i in range(500000):
        w.writerow([i, i * 1.1])
"
ls -lh large_sample.csv
```

**Step 3 — Track it with LFS *before* committing**

```bash
git lfs track "*.csv"
git add .gitattributes
git commit -m "Track CSV files with Git LFS"
```

`.gitattributes` is the file LFS uses to remember which patterns are tracked — commit it just like any other config file.

**Step 4 — Add and commit the large file**

```bash
git add large_sample.csv
git commit -m "Add large sample dataset via LFS"
git push origin main
```

> **Troubleshooting — "! [rejected] main -> main (non-fast-forward)"**
> GitHub has a commit your local `main` doesn't have yet — likely from a resolution or revert earlier in this session that made it to the remote but not back into this local sequence. Pull before pushing:
> ```bash
> git pull origin main
> ```
> This either fast-forwards cleanly, or opens a real conflict to resolve the same way as before (read the markers, edit by hand, `git add`, commit). Once `git status` is clean, push again:
> ```bash
> git push origin main
> ```

**Step 5 — Confirm it's actually using LFS, not raw git**

```bash
git lfs ls-files
```

You should see `large_sample.csv` listed. If you check the repo's actual git object for that file, it'll be a small pointer file, not the full 10MB+ CSV.

> **Important:** `git lfs track` only affects files added *after* you run it. If a large file was already committed with regular git before you set up LFS, tracking it now doesn't retroactively shrink your history — that requires rewriting history (out of scope for this goal, and risky on a shared repo).

> **Why this matters for you specifically:** you've already pushed 650MB to your Snowflake workbook repo without LFS. That works, but it's exactly the situation LFS is built for — worth considering for any future large sample datasets across the series.

---

## Concept Check

1. Why does `git fetch` never lose local work, but `git pull` sometimes can?
2. You made three commits locally, haven't pushed yet, and want to completely erase the last two along with their changes. Which command?
3. You pushed a bad commit yesterday and a teammate already pulled it. Which command do you use to undo it, and why not the other one?
4. If you run `git lfs track "*.csv"` today, does it retroactively fix a CSV you committed with plain git last month?

---

## Workbook complete

That's all three goals — Git Basics & Repo Setup, Branching Without Fear, and Staying in Sync & Undoing Mistakes. Between them, a newbie now has everything needed to clone, branch, commit, resolve a conflict, sync safely, undo a mistake without panic, and handle an oversized file — enough to walk into Workbook 01 (Snowflake) without git being the thing that trips them up.
