# OuterView

A native macOS interview-preparation app. Requires macOS 26.0 or later.
See [SPEC.md](SPEC.md) for the product specification.

## v1 workflow

1. Create a training set. Add groups and questions; use **Crop from PDF…** to
   select a handout, browse pages, and drag one passage rectangle per group.
2. Save the set. Open it from the recent-sets launch screen and press **Start**.
   Groups with passages begin with a reading timer; **Next** reveals questions.
3. Use **Devices** to select a camera/microphone. Hardware stays off on the deck;
   **Start** activates it for training (and requests permission if needed).
   **Record** and **Stop** save an independent take without advancing.
   **End Training**, **Finish Group**, changing groups, or leaving practice turns
   capture off. Navigation and closing are blocked while recording/saving.
   Otherwise, close/quit waits asynchronously for camera cleanup.
4. Play or retry takes from the current question’s takes panel. **Export** writes
   an H.264 MP4 with a three-second question title card, sequential filename,
   and selectable 540p, 720p (default), or 1080p quality.
5. Right-click a set on the launch screen to edit, export, or delete it. Import a
   friend’s `.outerview` file with a full review or blind import showing only counts.

Camera and timer eye controls affect their displays only. Passage/question
visibility and default export quality live in Settings (`⌘,`).
**Explore a Sample** creates a saved example set for trying the workflow.

## Storage and recovery

Sets persist with SwiftData, with explicit ordering and last-opened dates.
Cancel in the editor leaves saved content unchanged. Reordering preserves
question identity and its takes. Deletion cascades to associated records and
removes unused media after a successful database save.

Under the sandbox’s Application Support/OuterView directory:

- `Library.store`: metadata (including SQLite companion files).
- `Assets/<set UUID>/images` and `videos`: media referenced by relative paths.
- `PendingRecordings`: recovery journals and recordings awaiting a successful save.

Failed take saves offer **Retry Save**. On launch, playable pending movies are
reattached to their questions. Unreadable interrupted movies are retained and
reported. Cleanup preserves journal-protected media. Camera access is shut down
when training ends or you leave a workspace, including when permission/setup
finishes late. Device selection alone does not activate capture.

## Shared-set format

`.outerview` is a standard ZIP archive with UTF-8 names and uncompressed (STORE)
entries, containing `manifest.json` (version 1) and PNG passage images.
Groups/questions use explicit zero-based order values. Local IDs, recency, and
recordings are excluded. Imports receive fresh IDs.

Import validates size limits (200 MB, 1,000 groups, 5,000 questions), entry names,
checksums, image dimensions, and ordering before saving anything. ZIP64,
encrypted, and recompressed archives are unsupported: share the exported file
directly without re-zipping it.

## Development and verification

Open `OuterView.xcodeproj` and run the `OuterView` scheme. Choose a development
signing identity in Xcode to test the sandboxed camera/microphone permission flow.
All six implementation passes are implemented. Commit each completed pass after
its relevant checks pass.

The `OuterViewTests` target covers persistence/reopen, editing and ordering,
record preservation, cascading deletion, asset cleanup, crop coordinates,
session transitions and recording locks, camera activation/cancellation and
shutdown races, interrupted-save journals, ZIP
interoperability and invalid imports, and real synthetic H.264/AAC export.
Media tests verify title duration, decoded frames, silent title audio, audible
answer audio, and cancellation; exported frames/movie are attached to test results.

Visual checks cover the welcome screen, editor and PDF crop, passage/question
navigation, visibility controls, device selection, sharing/blind import, and
exported English/Korean title frames. Physical camera/microphone capture and
unplugging devices still require a hardware acceptance check; automated media
checks use synthetic recordings. Distribution packaging/notarization is not
part of this implementation pass.
