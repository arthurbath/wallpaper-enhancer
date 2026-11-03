# wallpaper-enhancement Specification

## Purpose
Provide a native macOS workflow for reliably improving individual and batch wallpaper images at a consistent size and selectable quality.

## Requirements

### Requirement: Import and review images
The application SHALL import selected or dropped files and folders, show thumbnails and per-image estimates, and warn about weak sources and duplicates within the current session. Every ready row SHALL join the next explicitly confirmed batch without an inclusion control. Completed rows SHALL remain visible for the session and SHALL NOT be enhanced again automatically. Failed or uncertain requests SHALL require an explicit retry.

#### Scenario: Duplicate source
- **WHEN** an imported file matches a source or result in the current session
- **THEN** it is flagged, remains eligible, and the paid-batch confirmation warns that it will receive a fresh enhancement

#### Scenario: Weak source
- **WHEN** the source is small, has little detectable detail, or needs substantial framing changes
- **THEN** the application explains the concern and permits enhancement

#### Scenario: Delete a selected image
- **WHEN** the user selects an image in the left rail and presses Delete while no batch is running
- **THEN** the row and its temporary artifacts are removed, original files and deposited outputs remain intact, and an unsaved returned result requires explicit discard confirmation

#### Scenario: Reopen a previously excluded image
- **WHEN** a saved ready image from an earlier version has a legacy exclusion flag
- **THEN** it is discarded with the ordinary prior-session queue on fresh launch

#### Scenario: Completed history
- **WHEN** completed and ready images appear together
- **THEN** only ready images contribute to the next batch and its estimate

### Requirement: Balanced square framing
The application SHALL preserve the source center and match total pixels cropped along the long dimension to total pixels added along the short dimension, before requesting a 2,880 × 2,880 result.

#### Scenario: Landscape framing
- **WHEN** the source is 4,000 × 2,000
- **THEN** 500 pixels are cropped from each side and 500 pixels are added above and below before scaling to the requested output

#### Scenario: Portrait framing
- **WHEN** the source is 2,000 × 4,000
- **THEN** the equivalent centered cropping and expansion applies on the opposite axes

### Requirement: Explicit paid enhancement
The application SHALL show individual and batch estimates before the user starts enhancement. It SHALL use GPT Image 2.5 Sunburst with selectable Low, Medium, High, Extra-high, and Maximum quality, default to Extra-high, and preserve 2,880 × 2,880 opaque PNG output. It SHALL distinguish usage-based actual cost from estimates and unknown charges.

#### Scenario: Import only
- **WHEN** images are added to the queue
- **THEN** no paid request starts until the user chooses Enhance and confirms the estimate

#### Scenario: Change quality before enhancement
- **WHEN** the user selects another quality in the main window or Settings
- **THEN** every pending per-image estimate and batch total updates before submission, the preference survives relaunch, and Maximum is identified as the highest available quality

#### Scenario: Review and submit a batch
- **WHEN** the user chooses Enhance
- **THEN** the confirmation shows the chosen quality, estimated cost per image, and total in USD, explains that estimates include inputs and outputs and are not spending limits, and submits only the reviewed images with that quality

#### Scenario: Processing a batch
- **WHEN** a batch is running
- **THEN** quality changes are disabled and every request uses the confirmed quality

### Requirement: Verified results and durable saving
The application SHALL verify an opaque PNG at the requested actual pixel size and quality, save successful results to the remembered destination with collision-safe hash names, and preserve original source files. Recovery SHALL verify against the original requested quality even if the current preference changes. Legacy responses SHALL retain the Extra-high expectation.

#### Scenario: Output folder unavailable
- **WHEN** OpenAI returns a valid image but the destination cannot be written
- **THEN** the image and usage receipt remain available for saving again without another generation charge

#### Scenario: Existing filename
- **WHEN** a hash-named file already exists
- **THEN** it is reused only for identical bytes, otherwise a different hash name is used without overwriting existing content

#### Scenario: Recovery after a quality change
- **WHEN** a Maximum response is retained and the current quality becomes Low
- **THEN** the retained response is verified as Maximum and can be saved without a new paid request

#### Scenario: Returned quality differs from requested quality
- **WHEN** the API returns Extra-high for a Maximum request
- **THEN** the response remains available for review and is not marked as a verified Maximum result or generated again automatically

### Requirement: Clear failures and safe recovery
The application SHALL show per-image failures during the current session, permit explicit retries, continue independent items when practical, and explain when an interrupted request may have incurred a charge. Unsaved returned results SHALL survive restart for saving or review without automatic generation.

#### Scenario: Interrupted generation
- **WHEN** the app restarts after a request was in progress without a recovered image
- **THEN** the new session explains the uncertainty once, does not restore the ordinary queue, and does not automatically resubmit the request

#### Scenario: Undelivered returned image
- **WHEN** a returned image has not been deposited in the selected destination
- **THEN** it remains available after restart until it is saved or explicitly discarded

### Requirement: Local installation
The app SHALL support installation in Applications with an explicitly configured stable code-signing identity. The source and specification SHALL support development independently of any machine-specific home directory or cloud-storage location. Packaging SHALL compile the supplied `Resources/App Icon.icon` document into the application icon. Credentials SHALL come from the user's Settings entry and SHALL NOT depend on an unrelated developer Keychain item.

#### Scenario: Local signing configuration
- **WHEN** the app is packaged
- **THEN** it uses the certificate display name from the explicit environment setting or ignored local configuration and verifies the complete signature without falling back to ad-hoc signing

#### Scenario: Signing identity unavailable
- **WHEN** the signing identity is not configured or the configured identity is unavailable
- **THEN** packaging stops with an actionable error and the installed application remains unchanged

#### Scenario: Credential denied
- **WHEN** macOS does not permit reading the app's saved credential
- **THEN** the user receives an actionable error and no generation request is made

#### Scenario: Supplied icon
- **WHEN** the application is packaged
- **THEN** its compiled icon resources come from the supplied Icon Composer document and the previous generated artwork is absent

### Requirement: Bounded session storage
The application SHALL remember the output folder and keep ordinary queues and duplicate records only in memory. It SHALL remove temporary images and receipts after delivery, clear stale caches on startup and quit, and migrate legacy stores. Diagnostics SHALL omit image data and source identities and SHALL be limited to 100 entries and 64KiB. Cleanup SHALL preserve original files and deposited outputs.

#### Scenario: Fresh launch
- **WHEN** a session starts with no unsaved returned result
- **THEN** the queue is empty, destination preferences are retained, and historical rows and stale image caches are removed

#### Scenario: Successful delivery
- **WHEN** an enhanced image is deposited in the requested destination
- **THEN** the app removes its recovery image, framing preview, request body, and receipt while the delivered image remains available

#### Scenario: Repeated use
- **WHEN** many images are successfully processed over multiple sessions
- **THEN** saved queues, temporary image copies, and receipt archives do not accumulate and diagnostic limits are enforced

### Requirement: User API key settings
The application SHALL provide masked OpenAI API key entry, saving, replacement, and removal in Settings. It SHALL manage secure local credential storage automatically. Keys SHALL NOT appear in app state, diagnostics, reports, source, or distributed bundles. Configuration changes SHALL be disabled during processing. Saving a key SHALL NOT start an API request or claim that account access has been verified.

#### Scenario: First setup
- **WHEN** no app-owned key has been saved
- **THEN** imports and estimates remain available, new paid batches are disabled, and the main window offers a Settings link

#### Scenario: Save or replace a key
- **WHEN** the user enters a key and chooses Save Key
- **THEN** the app stores it securely, clears the masked draft, and uses it for the next explicitly confirmed batch

#### Scenario: Remove a key
- **WHEN** the user chooses Remove Key
- **THEN** only the app-owned credential is removed, future paid batches are disabled, and existing returned images remain savable

#### Scenario: Relaunch
- **WHEN** the app relaunches after a key has been saved
- **THEN** it recognizes the saved credential without revealing the value in Settings

#### Scenario: No developer credential dependency
- **WHEN** the application runs on a Mac without unrelated developer credential items
- **THEN** entering the user's own key in Settings is sufficient for credential configuration
