# Goal 2: Branching Without Fear

**Workbook:** Git for Data Engineers (Workbook 00)
**Prerequisites:** Goal 1 complete — `de-git-sandbox` repo exists, pushed to GitHub, with `extract.py`, `transform.py`, `load.py`, `config.yaml`, `sample_data.csv`, `.gitignore`

---

## What this goal covers

Creating and switching branches · merging cleanly · causing (and resolving) a real merge conflict on purpose · expanding `.gitignore` for real data-engineering artifacts

Merge conflicts are the single biggest thing that scares git beginners into avoiding branches altogether. This goal deliberately creates one in a safe sandbox so the first time you see `<<<<<<< HEAD` isn't during a real deadline.

---

## 2.1 — Create a Branch for Your Own Work

**Step 1 — Confirm you're on `main` and it's clean**

```bash
cd de-git-sandbox
git status
git branch
# * main
```

**Step 2 — Create and switch to a feature branch**

```bash
git checkout -b feature/add-validation
```

This is shorthand for `git branch feature/add-validation` + `git checkout feature/add-validation` in one step. Confirm:

```bash
git branch
#   main
# * feature/add-validation
```

**Step 3 — Make a real change on this branch**

Add a basic validation check to `transform.py`:

```bash
cat > transform.py << 'EOF'
def transform(records):
    print("Transforming records...")
    for r in records:
        if r["value"] < 0:
            raise ValueError(f"Negative value in record {r['id']}")
    return [{**r, "value": r["value"] * 1.1} for r in records]
EOF
```

**Step 4 — Stage, commit, push the branch**

```bash
git add transform.py
git commit -m "Add validation check to transform step"
git push -u origin feature/add-validation
```

**Step 5 — Look at what you have now**

```bash
git log --oneline --graph --all
```

You should see `main` and `feature/add-validation` pointing at different commits, diverging from a shared point. This is the shape of almost all real git work — a stable line (`main`) and a branch where changes happen before they're proven safe.

> **Troubleshooting — "error: pathspec 'feature/add-validation' did not match any file(s) known to git"**
> This means `checkout -b` failed silently earlier or you typed `checkout` instead of `checkout -b` and the branch doesn't exist yet. Run `git branch` to see what actually exists.

---

## 2.2 — Merge, and Resolve a Conflict on Purpose

Here's where most tutorials fake it. We're not going to. You're going to cause a real conflict and fix it with your own hands.

**Step 1 — Go back to `main` and change the *same lines* differently**

```bash
git checkout main
```

Now edit `transform.py` on `main` — but change the *same function* in a way that's incompatible with what the branch did:

```bash
cat > transform.py << 'EOF'
def transform(records):
    print("Transforming records with 15% markup...")
    return [{**r, "value": r["value"] * 1.15} for r in records]
EOF
```

```bash
git add transform.py
git commit -m "Change markup rate to 15% on main"
```

Both `main` and `feature/add-validation` have now edited the same lines of `transform.py` in different, incompatible ways. This is exactly how real conflicts happen — two people (or two branches of your own work) touching the same code before syncing.

**Step 2 — Attempt the merge**

```bash
git merge feature/add-validation
```

Git will stop and report something like:

```
Auto-merging transform.py
CONFLICT (content): Merge conflict in transform.py
Automatic merge failed; fix conflicts and then commit the result.
```

This is not an error you did something wrong. This is git correctly refusing to guess which version you want.

**Step 3 — Open the file and read the conflict markers**

```bash
cat transform.py
```

You'll see something like:

```python
def transform(records):
<<<<<<< HEAD
    print("Transforming records with 15% markup...")
    return [{**r, "value": r["value"] * 1.15} for r in records]
=======
    print("Transforming records...")
    for r in records:
        if r["value"] < 0:
            raise ValueError(f"Negative value in record {r['id']}")
    return [{**r, "value": r["value"] * 1.1} for r in records]
>>>>>>> feature/add-validation
```

- Everything between `<<<<<<< HEAD` and `=======` is what's currently on the branch you're merging *into* (`main`).
- Everything between `=======` and `>>>>>>> feature/add-validation` is what's coming *from* the branch you're merging *in*.

**Step 4 — Resolve it by hand**

The real answer here is usually "keep both intents" — the validation check *and* the correct markup rate. Rewrite the function combining them, and delete all three marker lines completely:

```bash
cat > transform.py << 'EOF'
def transform(records):
    print("Transforming records with 15% markup...")
    for r in records:
        if r["value"] < 0:
            raise ValueError(f"Negative value in record {r['id']}")
    return [{**r, "value": r["value"] * 1.15} for r in records]
EOF
```

**Step 5 — Mark it resolved and commit**

```bash
git add transform.py
git status
# All conflicts fixed but you are still merging.

git commit -m "Merge feature/add-validation: combine validation with 15% rate"
```

No `-m` message is required here technically (git pre-fills a merge message), but writing your own is worth the habit.

**Step 6 — Push and clean up**

```bash
git push origin main                              # send the merge commit to GitHub
git branch -d feature/add-validation               # delete the branch locally (safe: only works if it's fully merged)
git push origin --delete feature/add-validation    # delete the branch on GitHub too
```

> **Troubleshooting — "you have not concluded your merge (MERGE_HEAD exists)"**
> You tried to run another git command mid-conflict before finishing. Finish resolving the conflict, `git add` the file, and commit before doing anything else.

> **Troubleshooting — merge markers left in the file by accident**
> If you commit without deleting `<<<<<<<` / `=======` / `>>>>>>>`, the file will run (or fail) with garbage syntax in it. Always re-read the whole function before staging, not just the conflicted lines.

---

## 2.3 — `.gitignore` for Real Data Engineering Artifacts

Goal 1 gave you a basic `.gitignore`. Data pipelines generate a specific set of junk that's worth knowing by name.

**Step 1 — Simulate the artifacts a real pipeline leaves behind**

```bash
mkdir output
echo "id,value,loaded_at" > output/load_results.csv
echo "SECRET_KEY=abc123" > .env
echo "connection failed at 10:32am" > pipeline.log
mkdir __pycache__
touch __pycache__/transform.cpython-311.pyc
```

**Step 2 — Check what git sees**

```bash
git status
```

`.env` should already be ignored from Goal 1. But `output/`, `pipeline.log`, and `__pycache__/`'s contents may still show as untracked, depending on your original patterns.

**Step 3 — Expand `.gitignore` properly**

```bash
cat > .gitignore << 'EOF'
# Python
__pycache__/
*.pyc

# Secrets and local config
.env
config.local.yaml

# Pipeline runtime artifacts — never commit generated output or logs
output/
*.log

# OS cruft
.DS_Store
EOF
```

**Step 4 — Confirm it worked**

```bash
git status
```

`output/`, `.env`, `pipeline.log`, and the `__pycache__` folder should no longer appear as untracked. Only the `.gitignore` change itself should show.

**Step 5 — Commit the updated `.gitignore`**

```bash
git add .gitignore
git commit -m "Expand .gitignore for pipeline output, logs, and secrets"
git push origin main
```

> **Important — `.gitignore` only works going forward.** If a file was already committed before you added it to `.gitignore`, git keeps tracking it. Here's what that mistake actually looks like, and how to fix it, simulated on `.env`.
>
> First, simulate forgetting to ignore it — temporarily remove the `.env` line from `.gitignore`, then add a fake secret to the file:
> ```bash
> # remove the ".env" line from .gitignore manually, then:
> echo "PASSWORD=123" >> .env
> ```
>
> Stage and check what git sees:
> ```bash
> git add .env
> git status
> ```
> `.env` now shows as a new file staged for commit — because it's no longer in `.gitignore`, git has no reason to skip it.
>
> Commit it — this is the accident:
> ```bash
> git commit -m "Add env config"
> ```
>
> **Oops.** You now have a secret sitting in your commit history. `git status` will show a clean tree — git thinks everything's fine, which is exactly the danger.
>
> Now fix it. Put `.env` back in `.gitignore`, then untrack the file without deleting it:
> ```bash
> # add ".env" back to .gitignore manually, then:
> git rm --cached .env                     # stop tracking it going forward — keeps the file on disk, just untracks it
> git commit -m "Stop tracking .env"
> ```
>
> Confirm:
> ```bash
> git status
> cat .env
> ```
> `.env` no longer appears in `git status` — but `cat .env` shows the file is still sitting right there on disk with `PASSWORD=123` in it, untouched. `git rm --cached` only removes it from git's tracking.
>
> **One thing this does *not* fix:** the earlier commit with `.env` in it still exists in history. Anyone with access to the repo could check out that old commit and see the secret. If a real secret ever gets committed, rotate/invalidate it immediately — removing it from a future commit doesn't undo the exposure.

---

## What If You Already Pushed It?

Everything above assumes you caught the mistake locally, before pushing. If `git push` already happened, the situation is worse — and `git rm --cached` alone does not fix it.

**Why it's worse once it's pushed:**

- The commit containing `.env` still exists in the remote's history, even after you push a new "fix" commit on top of it. `git rm --cached` only changes what's tracked *going forward* — it doesn't erase the earlier commit.
- Anyone who already cloned, fetched, or forked the repo has that commit too, sitting on their own machine, independent of anything you do next.
- If the repo is public, treat the secret as seen. Bots actively scan public GitHub repos for exposed credentials, often within minutes of a push — this isn't a hypothetical risk.

**The two things you actually need to do, in this order:**

1. **Rotate the secret immediately.** Change the password, revoke the API key, whatever it was — this is not optional and doesn't wait on step 2. A secret that left your machine is compromised the moment it's pushed, regardless of what you do to git history afterward.
2. **Clean up history, if you want to** (optional, and only after step 1). This requires rewriting history with a tool like `git filter-repo` or BFG Repo-Cleaner, followed by a force-push. It's out of scope for this workbook, but the short version: it removes the secret from *your* remote's history going forward, but can't reach copies others already pulled, and GitHub may retain references (old PR diffs, cached views) for a period regardless.

**The one-sentence rule to remember:** rewriting history is cleanup; rotating the secret is the actual fix. Never treat step 2 as a substitute for step 1.

---

## Concept Check

1. Why does git refuse to auto-resolve a conflict instead of just picking one side?
2. In the conflict markers, which side is `HEAD` and which side is the branch name — and why does that direction matter?
3. If you'd committed `.env` *before* adding it to `.gitignore`, would adding the pattern now remove it from history? Why or why not?
4. What's the practical difference between `git branch -d` and `git branch -D`?

---

## What's next

**Goal 3 — Staying in Sync & Undoing Mistakes** covers pulling upstream changes, `reset` vs `revert` vs `checkout`, and Git LFS for the oversized files real pipelines eventually produce.
