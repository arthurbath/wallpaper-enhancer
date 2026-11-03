# Wallpaper Enhancer

A native macOS app for turning individual or batch wallpaper images into clean 2,880 × 2,880 repaints. It preserves the source's visual medium and uses GPT Image 2.5 Sunburst. Quality defaults to `xhigh` and can be adjusted up to `max`, the highest available setting.

## API Key Setup

Open Wallpaper Enhancer → Settings and paste your OpenAI API key into the masked field. Choose Save Key. You can replace or remove the key in the same panel. Each Mac user supplies their own key, and API usage is billed to that person's OpenAI account. No manual Keychain setup is required.

The app stores the key securely in an app-owned local Keychain item. It never embeds a key in the application, writes it to queue state or diagnostics, or includes it in shared project files. Saving a key does not verify account access or make an API request. The API project needs credits and access to the configured image model.

## Use

1. Drop images or folders into the window, or choose **Add Images**
2. Choose **Quality** in the main window or Settings, then review each image's square framing, warnings, and estimated API cost
3. Select an unwanted image in the left rail and press Delete to remove it from the queue
4. Choose the output folder, which defaults to Desktop and is remembered
5. Review the estimated cost per image and batch total, choose **Enhance**, then confirm the quality and cost

Every ready image in the left rail is included in the next batch. Completed images remain visible only for the current session and are never submitted again automatically. Relaunching starts with an empty queue, except for returned images that still need saving. Duplicate inputs retain a warning before batch confirmation. Removing a row preserves original images and generated files. Failed or uncertain requests still require an explicit retry.

Successful outputs are opaque PNG files named with full SHA-256 hashes. Existing files and original images are preserved. The result must actually decode to 2,880 × 2,880. The application never silently resizes an incorrect API result.

For a 4,000 × 2,000 source, the framing guide crops 500 pixels from each side and adds 500 pixels above and below. The resulting 3,000 × 3,000 composition is rendered at the requested output size. AI reconstructs the transparent guide bands and refines the retained scene.

## Costs and Recovery

The quality selector offers Low, Medium, High, Extra-high, and Maximum. Maximum is the highest available setting. Changing quality updates all pending image estimates and the batch total before submission. The preference survives relaunch and cannot change during processing. The final confirmation captures the reviewed images and quality.

Estimates include output-image tokens from the [official GPT Image 2.5 calculator](https://developers.openai.com/api/docs/guides/image-generation#gpt-image-25-and-gpt-image-2-output-tokens), estimated input-image tokens, and a prompt allowance. At 2,880 × 2,880, output tokens are 659 for Low, 1,483 for Medium, 5,930 for High, 10,542 for Extra-high, and 23,719 for Maximum. With the input allowances, Extra-high is approximately $0.33 per image and Maximum is approximately $0.73 per image. The app adds unrounded per-image estimates before rounding the batch total.

Usage receipts calculate costs from returned token counts at saved standard API rates. Estimates are not spending limits or billing-dashboard confirmations and do not incorporate account-specific discounts, credits, or taxes. Actual usage may vary. Saved pricing and calculator values were checked on 2026 Nov 2.

Each image is one independent paid request. Batches run sequentially. **Stop After Current** lets the in-progress image finish and save. A lost or interrupted response can have an unknown charge and is never automatically generated again. **Save Again** uses a recovered result and makes no API call.

The app remembers the output folder and keeps temporary request and preview files under `~/Library/Application Support/garden.bath.wallpaper-enhancer/`. Successfully saved images have their temporary preview, recovery image, and receipt removed immediately. Duplicate detection covers only the current session. Ordinary queue rows and completed history do not survive relaunch. Old previews, request bodies, receipts, and history are cleared on upgrade.

Returned images that have not been saved survive relaunch so **Save Again** can finish without another API charge. They retain the quality originally requested, so changing the next batch's quality does not affect recovery. Delete explicitly discards such a recovery copy after a warning. The app never deletes original files or images already deposited in the selected destination. Performance diagnostics contain only time, outcome, duration, cost, and request ID, with a maximum of 100 entries and 64KiB. No image data, filenames, source paths, or image hashes appear in those diagnostics. The key entered in Settings is read directly from the app-owned Keychain item into memory and sent only to the official OpenAI HTTPS endpoint. The app does not access pre-existing developer credential items.

## Build and Test

Requires Xcode with Apple's asset compiler and macOS 14 or later. The build compiles the supplied `Resources/App Icon.icon` document into native icon resources. The app has no package dependencies or external runtime. Before packaging, configure your stable local code-signing identity as described in [Development](docs/development.md).

```sh
./script/test.sh
./script/build_and_run.sh --verify
```

Build products stay in `~/Library/Caches/garden.bath.wallpaper-enhancer/Build/` to avoid iCloud metadata that prevents code signing. `WALLPAPER_ENHANCER_BUILD_DIR` can select another local build folder.

`script/build_and_run.sh` packages a real `.app`, signs it with the configured local identity, and verifies its stable `garden.bath.wallpaper-enhancer` identifier. `script/install.sh` installs the verified bundle in `/Applications`, preserves an identical installed build, and moves a superseded bundle to Trash after launch verification. Machine-specific editor actions and development settings stay in ignored files.

OpenSpec maintains the behavior contract under `openspec/`. Local development checkpoints are committed without pushing.

## Distribution

Recipients can configure their own API key through Settings. User keys and destination preferences are stored outside the application bundle and are not part of a copy of the app.

Local builds use the developer's configured code-signing identity. Public binary distribution requires an appropriate Developer ID signing and notarization workflow. This repository does not provide a notarized release. See [Apple's distribution guidance](https://developer.apple.com/developer-id/).

## Development Validation

The app accepts the development-only `--qa-manifest PATH` argument. The JSON manifest provides `inputs`, `outputFolder`, `stateFolder`, `resultFile`, and `budgetUSD`. Optional `quality` selects a quality value for that QA profile, and `autoStart: false` permits import and estimate checks without starting requests. It uses a separate local queue, isolated credential service, and the same production processing engine. Paid validation requires a separately authorized budget. Keep manifests, images, receipts, and validation reports under the ignored `.local/` directory. See [Development](docs/development.md) for the validation and publication checks.

The optional native Keychain integration check uses a uniquely named disposable dummy item and makes no API request:

```sh
WALLPAPER_ENHANCER_KEYCHAIN_QA=1 ./script/test.sh --filter systemKeychainCreatesReplacesAndRemovesOnlyItsOwnTestItem
```
