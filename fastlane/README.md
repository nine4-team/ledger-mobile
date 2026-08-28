fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios upload_testflight

```sh
[bundle exec] fastlane ios upload_testflight
```

Build and upload Ledger to TestFlight

### ios external_testflight

```sh
[bundle exec] fastlane ios external_testflight
```

Build, upload, wait for processing, and attach Ledger to external TestFlight groups

### ios build_testflight_ipa

```sh
[bundle exec] fastlane ios build_testflight_ipa
```

Internal lane; use scripts/release-testflight.sh --no-upload

### ios distribute_existing_external

```sh
[bundle exec] fastlane ios distribute_existing_external
```

Attach an already-uploaded Ledger build to external TestFlight groups

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
