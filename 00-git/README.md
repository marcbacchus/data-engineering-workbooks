# Git for Data Engineers

**Workbook:** 00 — Git for Data Engineers
**Status:** Goals 1-3 complete ✅

---

## What this workbook covers

Git fundamentals · SSH & GitHub setup · branching · merge conflicts (staged and resolved by hand) · staying in sync (pull/fetch) · undoing mistakes (reset, revert, checkout) · Git LFS for oversized files

This is Workbook 00 — the entry point for the entire series. If you're new to git, start here before Workbook 01 (Snowflake). Everything is built around a small, disposable sandbox ETL project (`extract.py`, `transform.py`, `load.py`) so every exercise feels like real data engineering work rather than a generic tutorial.

---

## Prerequisites

- None — this is designed for git beginners
- A GitHub account
- A terminal (macOS, Linux, or Windows with Git Bash / WSL)

---

## Goals

| # | Goal | Covers |
|---|---|---|
| 1 | [Git Basics & Repo Setup](./goal_1_git_basics_and_repo_setup.md) | Install & configure git, SSH keys, cloning a repo, first stage → commit → push |
| 2 | [Branching Without Fear](./goal_2_branching_without_fear.md) | Creating branches, a deliberate merge conflict resolved by hand, `.gitignore` for real pipeline artifacts |
| 3 | [Staying in Sync & Undoing Mistakes](./goal_3_syncing_and_undoing_mistakes.md) | Pull vs fetch, `reset` vs `revert` vs `checkout`, Git LFS for large files |

Each goal builds on the same sandbox repo (`de-git-sandbox`) — work through them in order.

---

## By the end of this workbook

You'll be able to clone a repo, branch off safely, commit and push your work, resolve a real merge conflict without panicking, stay in sync with a remote, undo a mistake with the right tool for the situation, and handle an oversized file with Git LFS — everything needed to work through Workbook 01 (Snowflake) without git being the thing that trips you up.

---

*Part of the [Data Engineering Workbook Series](https://github.com/marcbacchus/data-engineering-workbooks)*
