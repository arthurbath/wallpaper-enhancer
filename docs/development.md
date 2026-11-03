# Development

## Local Signing

Configure a stable code-signing identity from your login keychain before packaging. Create `.local/signing-identity` with the certificate's display name on a single line. Alternatively, set `WALLPAPER_ENHANCER_SIGNING_IDENTITY` for the build. An explicit environment setting takes precedence over the local file.

The local file holds only a certificate display name. API keys belong in the app's Settings and app-owned Keychain service. Private signing keys belong in Keychain. Neither belongs in a development configuration file.

The build stops if no identity is configured or the configured identity is unavailable. It does not fall back to ad-hoc signing. The complete app is signed with the stable `garden.bath.wallpaper-enhancer` identifier, strictly verified, and inspected for its designated requirement. Use the same identity for subsequent builds to preserve local permission continuity.

## Build and Validation

Run the unit tests and repository checks:

```sh
./script/test.sh
python3 script/check_publication.py
git diff --check
```

Package a signed app without installing or launching it:

```sh
./script/build_and_run.sh --package
```

Build products default to the local application cache. `WALLPAPER_ENHANCER_BUILD_DIR` can select an isolated scratch directory. Install only when requested with `script/install.sh`. Repository maintenance does not require replacing an installed application.

Unit tests use synthetic images, dummy credential values, and recorded transports. They do not make paid API requests. The optional Keychain integration test creates and removes only its own disposable dummy item. Paid validation requires separate authorization and an explicit budget.

## Private Development Files

Keep local instructions, signing settings, historical validation notes, QA manifests, private images, receipts, and diagnostic exports under `.local/`. Machine-specific Codex actions remain under the ignored `.codex/` directory. These files support local work and must not be added to the publication index or shared as a whole-directory archive.

The repository also ignores environment files, common credential and certificate exports, databases, logs, build products, and private input/output directories. Ignore rules do not remove files already tracked. Review the staged file list and run the publication check before committing.

## Publication Check

`script/check_publication.py` examines the current tracked files, new nonignored files, and every blob and commit reachable from local Git refs. It flags common credential formats, private-key headers, personal home-directory paths, disallowed local artifacts, and non-noreply commit email addresses. It reports only rule names and locations, never candidate credential values. The exact dummy key fixtures are allowed only in their test file and the guard's own fixture list.

The check is a focused safeguard. Review new files and staged changes as part of normal development, and keep real credentials outside the repository even when a file is ignored. Use a GitHub noreply email address in this repository's local Git configuration to avoid publishing a personal contact address.
