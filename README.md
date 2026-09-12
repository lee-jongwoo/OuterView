# OuterView

The ultimate interview-preparation suite.

## Overview

The main purpose of this app is to help students prepare for in-person interviews. Consult SPEC.md for implementation details.

## Status Quo

The first SwiftUI shell is ready for layout review: an Xcode-style training-set
launch screen, a set editor, and a practice workspace with question navigation,
visibility controls, and a collapsible takes area. Choose **Explore a Sample**
to walk through the workspace without creating a set.

Training sets now persist locally with SwiftData, including last-opened dates and
explicit group/question ordering. The editor supports reordering and removal;
Cancel leaves saved content unchanged. Right-click a set on the launch screen to
edit or delete it. Deletion cascades to its records and cleans up unused assets.

The library lives under the sandbox's Application Support/OuterView directory:
`Library.store` holds metadata; `Assets/<set UUID>/images` and `videos` hold media.
Cleanup runs after successful changes and at startup to recover interrupted cleanup.
PDF cropping, shared-set import/export, camera recording, and video export are
not wired up yet. Recording remains disabled.

## Development checkpoints

Commit each completed implementation pass after its relevant checks pass.
Pass 1 (persistence) is complete. Next: PDF selection, page navigation, and cropping.

Run the `OuterViewTests` target for persistence/reopen, ordering, recording
preservation, cascading deletion, asset cleanup, and path validation coverage.

Open `OuterView.xcodeproj` and run the `OuterView` scheme on macOS 26.0 or later.
