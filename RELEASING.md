# Releasing Sill

Running [.github/workflows/release.yml](.github/workflows/release.yml) from `main` releases Sill. [git-cliff](https://git-cliff.org/) ([cliff.toml](cliff.toml)) picks the version from the conventional commits since the last tag: `fix:` and `perf:` make a patch release, `feat:` a minor one, and `!` or `BREAKING CHANGE:` a major one. When only other commits (`docs:`, `chore:` and so on) came after the last tag, the workflow releases nothing.

Then the workflow:

1. builds Sill with that version with Xcode 27.0 on the `xcode-27` runner (Apple silicon) with the same signing settings as `make install-sill-dev` in eai04191/dotfiles ([scripts/release/build.sh](scripts/release/build.sh)),
2. attests the zip with [actions/attest](https://github.com/actions/attest), so `gh attestation verify Sill-<version>.zip -R eai04191/sill` checks that the workflow built it,
3. creates a GitHub release with `Sill-<version>.zip` and the notes from git-cliff, which tags the commit with the version (barik's format, without a `v`),
4. pushes a `chore(release): <version>` commit to `main`, which does not count toward the next release. It adds the notes to the top of [CHANGELOG.md](CHANGELOG.md) ([scripts/release/prepend-changelog.sh](scripts/release/prepend-changelog.sh)) and points `Casks/sill.rb` at the zip ([scripts/release/write-cask.sh](scripts/release/write-cask.sh)).

This repository is the Homebrew tap: users run `brew tap eai04191/sill https://github.com/eai04191/sill` and install `eai04191/sill/sill`, and `brew upgrade` picks up the cask from `main`.

The version comes from the commits, so `MARKETING_VERSION` in Sill.xcodeproj is not bumped; the release build is given the version instead.

## Before the first release

The workflow lists everything below in its header comment.

1. Export the self-signed code signing certificate with its private key as a .p12 file with a password: in Keychain Access, select only that certificate under My Certificates and choose File → Export Items. The export must contain exactly one code signing identity.
2. Add these secrets to the `release` environment of eai04191/sill (Settings → Environments → release), which only `main` can deploy to:

   ```sh
   base64 -i sill-signing.p12 | gh secret set SIGNING_CERTIFICATE_P12_BASE64 --env release -R eai04191/sill
   pbpaste | gh secret set SIGNING_CERTIFICATE_PASSWORD --env release -R eai04191/sill  # the .p12 password, copied
   ```
3. Delete the exported .p12 file.

macOS ties permissions such as calendar access to the certificate: the designated requirement pins the certificate's SHA-1 (`codesign -d -r- Sill.app`). Keep using the same certificate for every release, and when its SHA-1 changes, users are asked for the permissions again. The workflow prints the SHA-1 in the "Import the signing certificate" step.

The repository's tag ruleset keeps release tags (`*.*.*`) from being deleted or moved, so a cask always points at the zip it was made for.

## Releasing

```sh
gh workflow run release.yml -R eai04191/sill --ref main
gh run watch -R eai04191/sill
```

Then check that the release has the zip and that `brew upgrade --cask sill` installs it.

If the `chore(release)` commit fails after the GitHub release is created, running the workflow again finds no new commits to release, so make the commit by hand on `main`: download the zip into `dist/` with `gh release download <version> -R eai04191/sill -D dist`, save the release's notes with `gh release view <version> -R eai04191/sill --json body --jq .body > dist/notes.md`, run `scripts/release/prepend-changelog.sh <version> dist/notes.md` and `scripts/release/write-cask.sh <version>`, and commit `CHANGELOG.md` and `Casks/sill.rb` as `chore(release): <version>`.

## Dependencies

Renovate ([.github/renovate.json](.github/renovate.json)) updates the actions and git-cliff, which the workflow pins with a version and the SHA-512 of its archive.
