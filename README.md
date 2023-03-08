# PolyglotRocks

<p align="left">
  <img alt="GitHub Workflow Status" src="https://img.shields.io/github/actions/workflow/status/clickcaramel/PolyglotRocks/test-branch.yml?label=tests">
  <img alt="GitHub" src="https://img.shields.io/github/license/clickcaramel/PolyglotRocks">
  <img alt="CocoaPods" src="https://img.shields.io/cocoapods/v/PolyglotRocks">
</p>

PolyglotRocks is a tool that simplifies the localization process for your iOS mobile app. By dropping in our SDK into your project and running the build, you can get AI translations instantly and manual ones a bit later.

## Contents

- [PolyglotRocks](#polyglotrocks)
  - [Contents](#contents)
  - [Vocabulary](#vocabulary)
  - [Integration options](#integration-options)
    - [Option 1. CocoaPods](#option-1-cocoapods)
    - [Option 2. cURL (Xcode)](#option-2-curl-xcode)
    - [Option 3. cURL (Manually)](#option-3-curl-manually)
    - [Option 4. GitHub Actions](#option-4-github-actions)
    - [Option 5. Docker](#option-5-docker)
  - [License](#license)

## Vocabulary

To use PolyglotRocks, you will need or may need the following parameters:

| Term | Description | Where to get |
| --- | --- | --- |
| `<your_token>` | The API token provided by PolyglotRocks. | Use the [official website](https://polyglot.rocks) to generate the API token for your tariff plan. |
| `<your_bundle_id>` | The product bundle identifier of the Xcode project. | 1) Open your Xcode project 2) In the Project Navigator select the project itself 3) Select the main project target 4) In the `General` tab a bundle identifier is under the `Identity` section. |
| `<path_to_files>` | The path to the directory to search files to be localized. | The path to the place where the tool will recursively search for your localization files, so you can specify any path along which it will be convenient to search for them. However, keep in mind that the path should not point to a directory containing several projects at once. |

These terms will be used further in integration options.

## Integration options

### Option 1. CocoaPods

To install PolyglotRocks, add the following line to your Podfile:

```ruby
pod 'PolyglotRocks'
```

Then, run `pod install` to install the library.

To use PolyglotRocks in your Xcode project, add the following command to the build phase:

```plain
"${PODS_ROOT}/PolyglotRocks/bin/polyglot" <your token>
```

### Option 2. cURL (Xcode)

To run PolyglotRocks on your local machine with Xcode, you can use a special script via cURL. To do this, add the following code to a build phase in your Xcode project:

```bash
/bin/bash -c "$(curl -fsSL https://polyglot.rocks/run.sh)" - <your_token>
```

This script will download the latest version of PolyglotRocks if needed and then will execute it at every build of your project using Xcode.

### Option 3. cURL (Manually)

Alternatively, you can run PolyglotRocks on your local machine as a regular tool in the terminal. Keep in mind that in this case you probably need to manually set the `PRODUCT_BUNDLE_IDENTIFIER` environment variable that Xcode usually deals with. For example, like this:

```bash
PRODUCT_BUNDLE_IDENTIFIER=<your_bundle_id> /bin/bash -c "$(curl -fsSL https://polyglot.rocks/run.sh)" - <your_token> <path_to_files>
```

> `<path_to_files>` is an optional parameter here.

### Option 4. GitHub Actions

The PolyglotRocks GitHub Action allows you to easily automate the localization process for your projects in CI/CD pipeline. Here is an example workflow for using the action in your GitHub Actions:

```yaml
name: Docker

on:
  pull_request:
    branches:
      - main

jobs:
  translate:
    runs-on: ubuntu-latest
    steps:
      # 1. Checkout latest version of your changes.
      - uses: actions/checkout@v3
      # 2. Run PolyglotRocks
      - uses: clickcaramel/PolyglotRocks@v0.1.7
        with:
          # The API token provided by PolyglotRocks.
          token: <your_token>
          # The product bundle identifier of the Xcode project.
          bundle_id: <your_bundle_id>
          # The path to the directory to search files to be localized (optional).
          path: <path_to_files>
```

**Keep in mind:** The PolyglotRocks GitHub Action does not automatically commit the changes made, so you may additionally need an extra workflow step to create a commit after the translation.

### Option 5. Docker

PolyglotRocks can also be used with Docker. To get started, pull the image from the repository by running the following command:

```bash
docker pull ghcr.io/clickcaramel/polyglot-rocks:0.1.7
```

Once you have pulled the image, you can run a Docker container with the following command:

```bash
docker run --rm \
    --env "TOKEN=<your_token>" \
    --env "PRODUCT_BUNDLE_IDENTIFIER=<your_bundle_id>" \
    --volume "<path_to_files>:/home/polyglot/target" \
    ghcr.io/clickcaramel/polyglot-rocks:0.1.7
```

**Keep in mind:** Docker uses absolute paths in volume mappings.

## License

**PolyglotRocks** is released under the Apache-2.0 license. See [LICENSE](./LICENSE) for details.
