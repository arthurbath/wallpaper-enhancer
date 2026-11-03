#!/usr/bin/env python3
"""Check publishable files and reachable Git history without printing secrets."""

import re
import subprocess
import sys
from pathlib import Path


RULES = {
    "provider-token": re.compile(
        rb"\b(?:sk-(?:proj-|svcacct-|ant-)?[A-Za-z0-9_-]{12,}"
        rb"|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"
        rb"|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}"
        rb"|(?:AKIA|ASIA)[0-9A-Z]{16}|npm_[A-Za-z0-9]{20,}"
        rb"|sb_secret_[A-Za-z0-9_-]{15,})\b"
    ),
    "private-key": re.compile(
        rb"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"
    ),
    "jwt": re.compile(
        rb"\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\."
        rb"[A-Za-z0-9_-]{12,}\b"
    ),
    "url-with-password": re.compile(
        rb"[a-zA-Z][a-zA-Z0-9+.-]*://[^\s/:@]+:[^\s/@]+@"
    ),
    "personal-home-path": re.compile(rb"/(?:Users|home)/[^/\s\"'<>]+"),
    "personal-signing-name": re.compile(
        rb"\b[A-Z][a-z]+ [A-Z][a-z]+ Personal Code Signing\b"
    ),
    "hardcoded-signing-identity": re.compile(
        rb"SIGNING_IDENTITY\s*=\s*[\"'](?!\$)[^\r\n\"']+[\"']"
    ),
    "contact-email": re.compile(
        rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"
    ),
}

# These exact, deliberately invalid fixtures are allowed only in their test file.
DUMMY_KEYS = {
    b"sk-dummy-app-key-not-real",
    b"sk-dummy-existing-not-real",
    b"sk-dummy-first-key-not-real",
    b"sk-dummy-metadata-test-not-real",
    b"sk-dummy-new-not-real",
    b"sk-dummy-not-real",
    b"sk-dummy-other-not-real",
    b"sk-dummy-replacement-not-real",
    b"sk-dummy-storage-boundary-not-real",
    b"sk-dummy-unrelated-not-real",
}
DUMMY_PATH = "Tests/EnhancerCoreTests/CredentialStoreTests.swift"
PRIVATE_PATH = re.compile(
    r"(?:^|/)(?:\.local|\.codex|\.build|dist|work|qa-results|inputs|outputs|"
    r"receipts|diagnostics|\.env[^/]*)(?:/|$)"
    r"|\.(?:pem|key|p12|pfx|cer|crt|mobileprovision|keychain(?:-db)?|"
    r"sqlite3?|db|log|bundle|dmg)$|\.app(?:/|$)|(?:^|/)\.DS_Store$",
    re.IGNORECASE,
)
NOREPLY = re.compile(rb"[A-Za-z0-9+_.-]+@users\.noreply\.github\.com")


def git(*args):
    return subprocess.check_output(["git", *args], stderr=subprocess.PIPE)


def inspect_content(data, location, path, findings):
    for rule, pattern in RULES.items():
        for match in pattern.finditer(data):
            value = match.group()
            if rule == "provider-token" and path == DUMMY_PATH and value in DUMMY_KEYS:
                continue
            # The guard contains its own exact fixture allowlist.
            if rule == "provider-token" and path == "script/check_publication.py" and value in DUMMY_KEYS:
                continue
            if rule == "contact-email" and NOREPLY.fullmatch(value):
                continue
            line = data[:match.start()].count(b"\n") + 1
            findings.add(f"{location}:{line}: {rule}")


def inspect_path(path, location, findings):
    if PRIVATE_PATH.search(path):
        findings.add(f"{location}: private-artifact-path")


def inspect_history(findings):
    objects = git("rev-list", "--objects", "--all").splitlines()
    checked = set()
    commits = 0
    blobs = 0
    for entry in objects:
        oid_bytes, _, name = entry.partition(b" ")
        oid = oid_bytes.decode("ascii")
        if oid in checked:
            continue
        checked.add(oid)
        kind = git("cat-file", "-t", oid).strip()
        if kind == b"blob":
            path = name.decode("utf-8", "replace")
            location = f"history/{oid[:10]}/{path}"
            inspect_path(path, location, findings)
            inspect_content(git("cat-file", "blob", oid), location, path, findings)
            blobs += 1
        elif kind == b"commit":
            data = git("cat-file", "commit", oid)
            headers, _, message = data.partition(b"\n\n")
            for field in (b"author", b"committer"):
                match = re.search(rb"(?m)^" + field + rb" [^\n]*<([^>]+)>", headers)
                if not match or not NOREPLY.fullmatch(match.group(1)):
                    findings.add(f"commit/{oid[:10]}: non-noreply-{field.decode()}-email")
            inspect_content(message, f"commit/{oid[:10]}/message", "", findings)
            # Walk every tree so a reused blob cannot hide under a private filename.
            for item in git("ls-tree", "-r", "--name-only", "-z", oid).split(b"\0"):
                if item:
                    path = item.decode("utf-8", "replace")
                    inspect_path(path, f"commit/{oid[:10]}/{path}", findings)
            commits += 1
        elif kind == b"tag":
            inspect_content(git("cat-file", "tag", oid), f"tag/{oid[:10]}", "", findings)
    return commits, blobs


def main():
    root = Path(git("rev-parse", "--show-toplevel").decode().strip())
    findings = set()
    paths = set(git("ls-files", "--cached", "--others", "--exclude-standard", "-z").split(b"\0"))
    files = 0
    for item in sorted(paths):
        if not item:
            continue
        path = item.decode("utf-8", "replace")
        file = root / path
        if not file.is_file():
            continue
        inspect_path(path, path, findings)
        inspect_content(file.read_bytes(), path, path, findings)
        files += 1
    commits, blobs = inspect_history(findings)
    if findings:
        print("Publication check failed. Candidate values are omitted.")
        for finding in sorted(findings):
            print(finding)
        return 1
    print(f"Publication check passed: {files} files, {commits} commits, {blobs} historical blobs.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, subprocess.CalledProcessError):
        print("Publication check could not complete. Check repository access.", file=sys.stderr)
        sys.exit(2)
