# Goal 1: Git Basics & Repo Setup

**Workbook:** Git for Data Engineers (Workbook 00)
**Prerequisites:** None — this is the entry point for the entire Data Engineering Workbook Series.

---

## What this goal covers

Installing and configuring git · SSH authentication with GitHub · cloning a real repo · the stage → commit → push cycle

By the end of this goal you'll have git installed, authenticated to GitHub, and will have made your first real commit and push — using a disposable sandbox project built to feel like an actual data pipeline, not a throwaway "hello world."

---

## The sandbox project

Before touching the real workbook repos, you'll build a tiny fake ETL project to practice on. This is **your own scratch repo** — nothing here is part of the Snowflake or Git workbook content itself, so there's no risk of breaking anything real.

This is a preview of the final structure — don't create anything yet. Step 1.3 below walks through creating each file with the actual commands.

```
de-git-sandbox/
├── extract.py       # pretend "pulls" data from a source
├── transform.py     # pretend "cleans" the data
├── load.py          # pretend "loads" it to a warehouse
├── config.yaml      # fake connection settings
├── sample_data.csv  # a few rows of throwaway data
└── .gitignore
```

You'll build this out across all three goals in this workbook — Goal 1 creates it, Goal 2 branches and merges it, Goal 3 syncs and recovers it.

---

## 1.1 — Install & Configure Git, SSH, and GitHub

**Step 1 — Create a GitHub account (skip if you already have one)**

Go to [github.com/signup](https://github.com/signup) and create a free account. A few things worth getting right at signup, since they're annoying to change later:

- Pick a username you'd be fine having on a resume or LinkedIn — recruiters and other engineers will see it on your commits and repos.
- Use an email you actually check — GitHub sends account verification and security notices to it.
- Free tier is all you need for everything in this workbook (and the rest of the series).

**Step 2 — Install git**

```bash
# macOS
brew install git

# Ubuntu/Debian
sudo apt update && sudo apt install git -y

# Windows
# Download from https://git-scm.com/download/win and run the installer
```

Verify it installed:

```bash
git --version
# git version 2.43.0 (or similar)
```

**Step 3 — Tell git who you are**

Every commit is stamped with this identity — get it right now, it's annoying to fix later across old commits.

```bash
git config --global user.name "Your Name"
git config --global user.email "your_email@example.com"
```

Confirm:

```bash
git config --global --list
```

**Step 4 — Generate an SSH key**

First, check whether you already have one — don't generate blind:

```bash
ls -la ~/.ssh
```

If you see `id_ed25519`, `id_rsa`, or similar files already there, you likely have a usable key already. Skip straight to Step 5 and use the existing one (`cat ~/.ssh/id_ed25519.pub` or the equivalent `.pub` file you found).

If nothing's there, generate a new one:

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
# Press Enter to accept the default file location
# Set a passphrase (recommended) or press Enter for none
```

`ed25519` is the key algorithm — a modern elliptic-curve type that's faster and cryptographically stronger than the older RSA default, and what GitHub recommends for new keys.

> **If you already have a key but want a separate one just for this workbook**, give it its own filename so `ssh-keygen` can't prompt to overwrite anything:
> ```bash
> ssh-keygen -t ed25519 -C "your_email@example.com" -f ~/.ssh/id_ed25519_workbook
> ```
> You'll then need to reference this file specifically when adding the key (Step 5) and may need an SSH config entry to use it by default — ask if you go this route and it's not picked up automatically.

**Step 5 — Add the key to GitHub**

```bash
cat ~/.ssh/id_ed25519.pub
```

Copy the output. On GitHub: **Settings → SSH and GPG keys → New SSH key** → paste it in.

**Step 6 — Test the connection**

```bash
ssh -T git@github.com
```

Expected output:

```
Hi <your-username>! You've successfully authenticated, but GitHub does not provide shell access.
```

> **Troubleshooting — "Permission denied (publickey)"**
> Almost always means the key wasn't added to the SSH agent. Run:
> ```bash
> eval "$(ssh-agent -s)"
> ssh-add ~/.ssh/id_ed25519
> ```
> Then retry Step 5.

---

## 1.2 — Clone a Repo & Understand the Structure

**Step 1 — Clone this repo (or any public repo, for practice)**

```bash
git clone git@github.com:marcbacchus/data-engineering-workbooks.git
cd data-engineering-workbooks
```

**Step 2 — Look around before you touch anything**

```bash
ls -la
git status
git log --oneline -10
```

`git status` should say `working tree clean` — you haven't changed anything yet, so git has nothing to report.

> **Stuck in the log view?** If `git log` opens a scrolling view that doesn't respond to normal typing, you're in git's default pager (`less`). Press `q` to exit back to your shell prompt. Arrow keys or `space` scroll up/down while you're in it, if you want to look further back first.

**Step 3 — Understand what you're looking at**

- `git log --oneline` shows the commit history — every saved snapshot, oldest work at the bottom.
- Folders map to workbooks (`00-git/`, `01-snowflake/`, etc.) — each workbook is self-contained.
- You are on the `main` branch by default. Check with:

```bash
git branch
```

> **Note:** Don't push directly to this repo yet — that's covered properly once branching (Goal 2) is in place. For now this step is just about reading a real repo's structure, not modifying it.

---

## 1.3 — Stage, Commit, Push: Your First Change

**Step 1 — Create the sandbox project**

```bash
mkdir de-git-sandbox && cd de-git-sandbox
git init
```

**Step 2 — Create the pipeline files**

```bash
cat > extract.py << 'EOF'
def extract():
    print("Extracting data from source...")
    return [{"id": 1, "value": 100}]
EOF

cat > transform.py << 'EOF'
def transform(records):
    print("Transforming records...")
    return [{**r, "value": r["value"] * 1.1} for r in records]
EOF

cat > load.py << 'EOF'
def load(records):
    print(f"Loading {len(records)} records to warehouse...")
EOF

cat > config.yaml << 'EOF'
warehouse: WORKBOOK_WH
database: ECOMMERCE
schema: RAW
EOF

echo "id,value" > sample_data.csv
echo "1,100" >> sample_data.csv
```

**Step 3 — Add a `.gitignore` before your first commit**

This matters more than it seems — commit a secrets file or a `__pycache__` folder once, and it lives in your history forever unless you rewrite it.

```bash
cat > .gitignore << 'EOF'
__pycache__/
*.pyc
.env
.DS_Store
EOF
```

**The four places a file can live**

Before staging and committing, it helps to see the whole path a file travels — this is where "why do I need both `add` and `commit`?" usually clicks:

```
 Working Directory        Staging Area           Local Repo             Remote Repo
 (your actual files)      (what's "ready")       (saved history)        (GitHub)

     transform.py  --add-->   transform.py  --commit-->  [snapshot]  --push-->  [snapshot]
      (edited)                  (staged)                  (committed)           (shared)
```

- **Working directory** — the files as they currently sit on your disk. Editing a file only changes this.
- **Staging area** — a holding pen for changes you've explicitly marked with `git add`. This is what the *next* commit will include — nothing more, nothing less.
- **Local repo** — the permanent history on your machine. `git commit` takes what's staged and saves it as a snapshot here, with a hash, a message, and a timestamp.
- **Remote repo** — the copy on GitHub. Nothing you commit locally is visible to anyone else until you `git push`.

This is also why `git status` is worth running constantly — it tells you what's sitting in each of the first three places at any given moment.

**Step 4 — Check status, stage, and commit**

```bash
git status
# Untracked files: extract.py, transform.py, load.py, config.yaml, sample_data.csv, .gitignore

git add .
git status
# Changes to be committed: (all files, staged in green)

git commit -m "Initial commit: sandbox ETL scaffold"
```

**Step 5 — Push it to GitHub**

Create an empty repo on GitHub first (no README, no .gitignore — you already have one), then:

```bash
git remote add origin git@github.com:<your-username>/de-git-sandbox.git
git branch -M main
git push -u origin main
```

Refresh the GitHub page — your files should be there.

> **Troubleshooting — "nothing to commit, working tree clean" after `git add .`**
> This means the files were already committed, or you're not in the directory you think you're in. Run `pwd` and `git log --oneline` to confirm where you are.

> **Troubleshooting — "src refspec main does not match any"**
> Means you tried to push before making a commit. Git has no `main` branch until the first commit exists. Go back to Step 4.

---

## Concept Check

Answer these before moving to Goal 2 — if any feel shaky, redo the relevant step rather than pushing forward.

1. What's the difference between `git add` and `git commit`?
2. Why does `.gitignore` need to be created *before* you commit a file you want ignored, not after?
3. What does `git status` tell you that `git log` doesn't, and vice versa?
4. If `ssh -T git@github.com` fails, what's the first thing to check?

---

## What's next

**Goal 2 — Branching Without Fear** picks up right here with this same sandbox repo: creating a branch, causing a deliberate merge conflict, and resolving it safely.
