# Wallpaper Enhancer

Read `.local/AGENTS.md` when it exists for machine-specific development conventions. Keep local instructions, settings, validation records, and repository backups private under the ignored `.local/` directory.

Keep the default GPT Image 2.5 Sunburst configuration: `xhigh`, `2880x2880`, opaque PNG. Quality is adjustable from `low` through `max`, with estimates shown before paid-batch confirmation. Use only the API key entered through Settings and managed in the app-owned Keychain service. Do not read or migrate unrelated developer credentials. QA profiles use an isolated credential service and dummy keys. Store credentials only in the app-owned Keychain and memory, and send them only in the HTTPS authorization header. Never write credentials to source, ordinary files, environment exports, arguments, or logs.

Use OpenSpec for maintained behavior. Keep application source under `Sources/`, tests under `Tests/`, and build tooling under `script/`. Run `script/test.sh`, `script/check_publication.py`, and `git diff --check` before a coherent local checkpoint. Stage explicit files after reviewing the diff. Never push, publish, or install without authorization.

Sign the complete app with the explicitly configured stable local identity and the identifier `garden.bath.wallpaper-enhancer`. Read the certificate display name from `.local/signing-identity` or `WALLPAPER_ENHANCER_SIGNING_IDENTITY`. Never fall back to an ad-hoc signature. Verify strictly and inspect the designated requirement before installation. Repository maintenance alone does not require replacing the installed app.

Preserve output-folder preferences, unsaved returned results, and originals. Queue rows and completed history are session-only. Purge temporary images and receipts after successful delivery, and cap diagnostics at 100 entries and 64KiB. A superseded installed bundle belongs in Trash after replacement verification.

No paid request may start just by importing images. Display the estimate before the Enhance action. An uncertain request must not automatically generate again. Recover a cached successful response by saving it, without another paid request.

Use synthetic fixtures for routine validation and require an explicit budget before paid API validation. No required owner acceptance testing.
