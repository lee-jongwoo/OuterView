# Releasing OuterView for macOS

The exported app is version 1.0.0 (build 1), supports Apple silicon and Intel,
and requires macOS 26.0 or later.

## Package

Export a Developer ID-signed, notarized app from Xcode. Do not edit its contents.
From the repository root:

```sh
bash scripts/package-dmg.sh
```

This verifies the app signature, stapled ticket and Gatekeeper acceptance, then
creates `dist/OuterView-1.0.0.dmg` with an Applications shortcut. It refuses to
overwrite an existing image. The app and `dist/` are gitignored.

## Sign and notarize the DMG

The app retains its notarization ticket inside the DMG. Apple's recommended
workflow also signs and notarizes the DMG container. The script does not do this.

```sh
security find-identity -v -p codesigning
```

You need a **Developer ID Application** identity, not Apple Development. If
missing, obtain one through Xcode's account certificate management, or import
the certificate and private key from the signing Mac. Use the app's developer
team. Never commit signing credentials or paste passwords into chat.

Store notarization credentials in Keychain interactively. This needs your Apple
account, team ID and app-specific password:

```sh
xcrun notarytool store-credentials OuterView-notary
```

Replace the signing identity placeholder with the exact identity from above:

```sh
codesign --force --timestamp --sign 'Developer ID Application: YOUR NAME (TEAMID)' dist/OuterView-1.0.0.dmg
xcrun notarytool submit dist/OuterView-1.0.0.dmg --keychain-profile OuterView-notary --wait
```

Continue only after **Accepted**. For a rejection, retrieve details with
`xcrun notarytool log SUBMISSION_ID --keychain-profile OuterView-notary`.

```sh
xcrun stapler staple dist/OuterView-1.0.0.dmg
xcrun stapler validate dist/OuterView-1.0.0.dmg
codesign --verify --verbose=2 dist/OuterView-1.0.0.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 dist/OuterView-1.0.0.dmg
(cd dist && shasum -a 256 OuterView-1.0.0.dmg > SHA256SUMS.txt)
```

Generate the checksum after signing and stapling, which change the file.

## GitHub release

Review and commit the release source first, including version/category changes.
Confirm the release commit corresponds to the exported app before tagging it.

After pushing that commit, replace the target placeholder with its full SHA:

```sh
gh release create v1.0.0 dist/OuterView-1.0.0.dmg dist/SHA256SUMS.txt \
  --repo lee-jongwoo/OuterView \
  --target FULL_RELEASE_COMMIT_SHA \
  --title 'OuterView 1.0.0' \
  --notes-file release-notes/1.0.0.md \
  --draft
```

Review the draft assets and notes. Test a browser-downloaded copy on another Mac
or clean user account: drag the app into Applications, eject the DMG, launch,
grant camera/microphone permissions, record, play back, export and relaunch.
Do not remove quarantine or disable Gatekeeper for this test. Packaging checks
verify integrity and notarization, not first-install functionality.

Publish the reviewed draft using GitHub's **Publish release** button. Upload the
DMG as a release asset; GitHub's automatic source archives are not the installer.

References: [Apple packaging guide](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution),
[Apple notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[GitHub release creation](https://cli.github.com/manual/gh_release_create).
