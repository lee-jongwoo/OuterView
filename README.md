# OuterView

The ultimate interview-preparation suite.

## Overview

The main purpose of this app is to help students prepare for in-person interviews. Consult SPEC.md for implementation details.

## Status Quo

The first SwiftUI shell is ready for layout review: an Xcode-style training-set
launch screen, a set editor, and a practice workspace with question navigation,
visibility controls, and a collapsible takes area. Choose **Explore a Sample**
to walk through the workspace without creating a set.

This pass uses in-memory content; changes last until the app quits. PDF cropping,
shared-set import/export, persistence, camera recording, and video export are not
wired up yet. Recording is disabled in the shell.

Open `OuterView.xcodeproj` and run the `OuterView` scheme on macOS 26.0 or later.
