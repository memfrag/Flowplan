---
name: ship-release
description: Build, notarize, and publish a new Flowplan release — bumps the version, archives the Release scheme, notarizes + staples the DMG, creates the GitHub release, and updates the Sparkle appcast via Scripts/build-and-notarize.sh. Use when asked to ship, cut, publish, or release a new version of the Flowplan macOS app.
---

# Ship a Flowplan release

Cut a new notarized, Sparkle-updatable release of the Flowplan macOS app. The heavy lifting is
`Scripts/build-and-notarize.sh`; this skill is the safe procedure around it.

## Credentials (must already exist on the machine — the user's local setup)

The script fails if these are missing; tell the user rather than trying to create them:
- Developer ID Application cert for team **CQXRBQKG85** (Martin Johannesson) — *not* the Apparata AB cert.
- Notary keychain profile: `xcrun notarytool store-credentials 'notary'`.
- Sparkle EdDSA keys in the keychain (`./Sparkle-tools/bin/generate_keys`).
- `gh auth login`.

## 1. Preflight

- **Clean tree on `main`**: `git status --short` must be empty. Commit/stash anything pending first.
- **Release build is green** (catches errors before the slow notarize):
  `xcodebuild -project Flowplan.xcodeproj -scheme "Flowplan (Release)" -destination 'platform=macOS' build`
- **CloudKit schema check (critical).** If any `@Model` *stored property* was added since the last
  release, the CloudKit **Production** schema must be promoted first (CloudKit Console → deploy
  Development→Production) or the new field silently won't sync. Check:
  `git diff --stat <lastTag>..HEAD -- '*/Models/*.swift'` and scan for new `public var`. If there are
  new stored properties, stop and tell the user to deploy the schema before shipping. (See the project
  memory on CloudKit schema rules.)

## 2. Version + notes

- Latest release: `gh release view --repo memfrag/Flowplan --json tagName -q .tagName`
  (or `git tag | sort -V | tail -1`). Next version = bump the patch (e.g. `1.0.5` → `1.0.6`).
  Confirm with the user if a minor/major bump might be intended.
- **Write release notes to a file** outside `build/` (the script does `rm -rf build` first) — the
  scratchpad is fine. Summarize user-facing changes from `git log --oneline <lastTag>..HEAD`.
  Flowplan commits direct-to-`main` (no PRs), so GitHub's `--generate-notes` produces empty notes —
  **always pass `--notes-file`**.

## 3. Run the script

`Scripts/build-and-notarize.sh` accepts `--version`, `--title`, `--notes-file` (each falls back to an
interactive prompt if omitted). It: bumps + commits + pushes the version → archives the Release scheme
→ exports with `-allowProvisioningUpdates` → notarizes + staples → builds + Sparkle-signs the DMG →
tags + pushes → `gh release create` → regenerates + commits `appcast.xml`.

Invoke it via the Bash tool with:
- `run_in_background: true` — archive + notarize takes several minutes.
- `dangerouslyDisableSandbox: true` — it needs the keychain (signing/notary/Sparkle), network, and git/gh push.
- stdout/stderr redirected to a log file you can Read to monitor.

```
./Scripts/build-and-notarize.sh --version <X.Y.Z> --title "Flowplan <X.Y.Z>" --notes-file <path> > <log> 2>&1
```

## 4. Watch & report

- Read the log. Success ends with `==> Done! Released Flowplan <X.Y.Z>` (exit 0).
- If the log stalls, a macOS keychain dialog is probably blocking a signing/notary/Sparkle step — tell
  the user to click **Always Allow**.
- On success, report the release URL `https://github.com/memfrag/Flowplan/releases/tag/<X.Y.Z>` and that
  the appcast was updated (existing users will get the update offer).

## Failure recovery

- The version bump is committed + pushed **before** build/notarize. If a later step fails, the version
  is already bumped on `main` — fix the cause and re-run with the same `--version`; the script reuses it
  and only tags when it reaches the release step.
- `No profiles for 'io.apparata.Flowplan'` at export → the script's `-allowProvisioningUpdates` handles
  it; ensure the Apple ID for team CQXRBQKG85 is signed into Xcode ▸ Settings ▸ Accounts.
- Team is **CQXRBQKG85**; the CloudKit container `iCloud.pizza.martin.Flowplan` is owned by that team.
  Do not switch to the Apparata AB (DR5YAK7GKS) cert — it would break iCloud.
