# Releasing Sill

Running [.github/workflows/release.yml](.github/workflows/release.yml) from `main` releases Sill. [git-cliff](https://git-cliff.org/) ([cliff.toml](cliff.toml)) picks the version from the conventional commits since the last tag: `fix:` and `perf:` make a patch release, `feat:` a minor one, and `!` or `BREAKING CHANGE:` a major one. When only other commits (`docs:`, `chore:` and so on) came after the last tag, the workflow releases nothing.

Then the workflow:

1. builds Sill with that version on `macos-26` (Apple silicon) with the same signing settings as `make install-sill` in eai04191/dotfiles ([scripts/release/build.sh](scripts/release/build.sh)),
2. attests the zip with [actions/attest](https://github.com/actions/attest), so `gh attestation verify Sill-<version>.zip -R eai04191/sill` checks that the workflow built it,
3. creates a GitHub release with `Sill-<version>.zip` and the notes from git-cliff, which tags the commit with the version (barik's format, without a `v`),
4. updates `Casks/sill.rb` in the tap ([scripts/release/update-tap.sh](scripts/release/update-tap.sh)).

The version comes from the commits, so `MARKETING_VERSION` in Sill.xcodeproj is not bumped; the release build is given the version instead.

## Before the first release

The workflow lists everything below in its header comment.

1. Create the tap repository `eai04191/homebrew-tap` (public, with at least one commit on the default branch). Users install from it as `eai04191/tap`.
2. Export the self-signed code signing certificate with its private key as a .p12 file with a password: in Keychain Access, select only that certificate under My Certificates and choose File → Export Items. The export must contain exactly one code signing identity.
3. Add these secrets to the `release` environment of eai04191/sill (Settings → Environments → release), which only `main` can deploy to:

   ```sh
   base64 -i sill-signing.p12 | gh secret set SIGNING_CERTIFICATE_P12_BASE64 --env release -R eai04191/sill
   pbpaste | gh secret set SIGNING_CERTIFICATE_PASSWORD --env release -R eai04191/sill  # the .p12 password, copied
   pbpaste | gh secret set TAP_GITHUB_TOKEN --env release -R eai04191/sill  # the token below, copied
   ```

   `TAP_GITHUB_TOKEN` is a fine-grained personal access token for `eai04191/homebrew-tap` only, with Repository permissions → Contents: Read and write.
4. Delete the exported .p12 file.

macOS ties permissions such as calendar access to the certificate: the designated requirement pins the certificate's SHA-1 (`codesign -d -r- Sill.app`). Keep using the same certificate for every release, and when its SHA-1 changes, users are asked for the permissions again. The workflow prints the SHA-1 in the "Import the signing certificate" step.

The repository's tag ruleset keeps release tags (`*.*.*`) from being deleted or moved, so a cask always points at the zip it was made for.

## Releasing

```sh
gh workflow run release.yml -R eai04191/sill --ref main
gh run watch -R eai04191/sill
```

Then check that the release has the zip and that `brew upgrade --cask sill` installs it.

If the cask update fails after the GitHub release is created, fix the cause, download the zip into `dist/` with `gh release download <version> -R eai04191/sill -D dist`, and run `scripts/release/update-tap.sh <version> <tap checkout>`, because running the workflow again finds no new commits to release.

## Dependencies

Renovate ([.github/renovate.json](.github/renovate.json)) updates the actions and git-cliff, which the workflow pins with a version and the SHA-512 of its archive.
