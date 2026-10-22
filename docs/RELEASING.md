# Releasing Shuro

Shuro releases are tag-driven. Pull requests and pushes to main run CI; only a v* tag runs the signed, multi-platform release pipeline.

## 1. Prepare a release commit

1. Merge the release changes into main and wait for **Shuro CI** to pass.
2. Update the version in pubspec.yaml on that commit.
3. Use the format **MAJOR.MINOR.PATCH+BUILD**, or **MAJOR.MINOR.PATCH-rc.1+BUILD** for a prerelease. Example: **2.5.1+10**.
4. Increase BUILD for every release. The release preflight checks that it is higher than the build number recorded by every existing v* release tag. Do not reuse an Android build number.

The v tag uses the version name but excludes the +BUILD suffix. For version **2.5.1+10**, the tag must be **v2.5.1**. For **2.6.0-rc.1+11**, the tag must be **v2.6.0-rc.1**.

## 2. Confirm Android signing secrets

Android signing secrets are optional. Configure all four to create upload-key-signed Android artifacts. If none are configured, the workflow still builds and publishes the Android APK/AAB using the Android Gradle project's default debug signing key; those Android artifacts are for testing only. The Windows installer and Linux package still build and publish normally. Configure all four or none—partial configuration fails preflight.

For upload-key-signed Android artifacts, configure these repository Actions secrets:

- **ANDROID_KEYSTORE_BASE64** — the upload keystore encoded as one Base64 string.
- **ANDROID_KEYSTORE_PASSWORD**
- **ANDROID_KEY_ALIAS**
- **ANDROID_KEY_PASSWORD**

For Linux, encode without line wrapping:

~~~bash
base64 -w 0 android/upload-keystore.jks
~~~

For macOS:

~~~bash
base64 -i android/upload-keystore.jks | tr -d '\n'
~~~

Copy the output directly into the secret value. Never commit the keystore, android/key.properties, or any password to the repository. Do not paste secrets into workflow logs or issues. The workflow decodes the keystore only on the Android runner and removes the temporary files after building. With no secrets, files are clearly named `*-debug-signed.apk` and `*-debug-signed.aab`, and the published release notes warn that the AAB is not suitable for Google Play. Do not upload debug-signed AABs to Google Play.

## 3. Tag the exact commit on main

From a clean local checkout after the version change has been merged:

~~~bash
git switch main
git pull --ff-only origin main
git tag -a v2.5.1 -m "Shuro v2.5.1"
git push origin v2.5.1
~~~

Replace v2.5.1 with the actual version name. The tag must point to a commit reachable from origin/main and match pubspec.yaml. Use a new version and a new tag for each release; do not move or reuse a published tag.

## 4. What the workflow does

1. Validates the tag, source branch ancestry, Android signing secrets, and increasing Android build number.
2. Runs Flutter analyze and tests.
3. Builds a signed Android APK and Play Store AAB, a Windows x64 installer, and a Linux amd64 Debian package.
4. Checks that every expected artifact exists, creates BUILD-INFO.txt and SHA256SUMS.txt, and uploads all assets to a draft release.
5. Verifies the release asset list, then publishes the release. A failed platform build or missing artifact prevents publication.

A prerelease version containing a hyphen (for example, 2.6.0-rc.1) is automatically marked as a prerelease.

## 5. Verify downloaded files

Place the downloaded release assets and SHA256SUMS.txt in the same directory, then run:

~~~bash
sha256sum --check SHA256SUMS.txt
~~~

The release contains:

- **\*-android.apk** — direct Android installation.
- **\*-android-play.aab** — upload to Google Play.
- **\*-windows-x64-setup.exe** — Windows installer.
- **\*-linux-amd64.deb** — Debian/Ubuntu package.
- **BUILD-INFO.txt** — version, tag, commit and workflow run metadata.

If a tag run fails, inspect Actions → Release for the first failed job, fix the cause on main, bump the version/build number, and tag a new release. Published releases are intentionally not overwritten.
