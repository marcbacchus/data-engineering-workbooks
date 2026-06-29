#!/usr/bin/env python3
"""
add_author_header.py
Adds an author attribution line to every SQL file in the repo.

Usage:
    python3 add_author_header.py /path/to/data-engineering-workbooks

Inserts the author line after the FIRST complete header block
(between the opening and closing ══════ lines at the top of the file).

Safe to run multiple times — skips files that already have the author line.
"""

import os
import sys

AUTHOR_LINE = "-- Author  : Marc Bacchus · github.com/marcbacchus/data-engineering-workbooks\n"
HEADER_MARKER = "══════"

def add_author_to_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    # Skip if author line already exists
    if any("Author  : Marc Bacchus" in line for line in lines):
        print(f"  SKIP (already has author): {filepath}")
        return False

    # Find the FIRST ══ line (opening of header)
    first_marker = None
    second_marker = None

    for i, line in enumerate(lines):
        if HEADER_MARKER in line:
            if first_marker is None:
                first_marker = i
            else:
                second_marker = i
                break  # Stop at second ══ — that is the end of the header block

    if second_marker is None:
        print(f"  SKIP (no complete header found): {filepath}")
        return False

    # Insert author line immediately after the closing ══ line
    lines.insert(second_marker + 1, AUTHOR_LINE)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.writelines(lines)

    print(f"  UPDATED: {filepath}")
    return True

def process_repo(repo_path):
    updated = 0
    skipped = 0

    for root, dirs, files in os.walk(repo_path):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d != 'node_modules']

        for filename in sorted(files):
            if filename.endswith('.sql'):
                filepath = os.path.join(root, filename)
                result = add_author_to_file(filepath)
                if result:
                    updated += 1
                else:
                    skipped += 1

    print(f"\nDone. Updated: {updated} files · Skipped: {skipped} files")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 add_author_header.py /path/to/repo")
        sys.exit(1)

    repo_path = sys.argv[1]
    if not os.path.isdir(repo_path):
        print(f"Error: {repo_path} is not a directory")
        sys.exit(1)

    print(f"Adding author attribution to SQL files in: {repo_path}\n")
    process_repo(repo_path)
