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
  - [Usage](#usage)
    - [CocoaPods](#cocoapods)
    - [GitHub Actions](#github-actions)
    - [Docker](#docker)
  - [License](#license)

## Usage

### CocoaPods

To install PolyglotRocks, add the following line to your Podfile:

```ruby
pod 'PolyglotRocks'
```

Then, run `pod install` to install the library.

To use PolyglotRocks in your Xcode project, add the following command to the build phase:

```plain
"${PODS_ROOT}/PolyglotRocks/bin/polyglot" <your token>
```

Replace `<your token>` with the API token provided by PolyglotRocks.

### GitHub Actions

The PolyglotRocks GitHub Action allows you to easily automate the localization process for your projects in CI/CD pipeline. Here is an example workflow for using the action in your GitHub Actions:

```yaml
jobs:
  translate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: clickcaramel/PolyglotRocks@v0.1.6
        with:
          path: <path_to_project>
          token: <your_token>
          bundle_id: <your_bundle_id>
```

> Replace `<your_token>`, `<your_bundle_id>`, and `<path_to_project>` with your API token, product bundle identifier, and the path to your Xcode project, respectively.

### Docker

PolyglotRocks can also be used with Docker. To get started, pull the image from the repository by running the following command:

```bash
docker pull ghcr.io/clickcaramel/polyglot-rocks:0.1.6
```

Once you have pulled the image, you can run a Docker container with the following command:

```bash
docker run --rm \
    --env "TOKEN=<your_token>" \
    --env "PRODUCT_BUNDLE_IDENTIFIER=<your_bundle_id>" \
    --volume "<path_to_project>:/home/polyglot/target" \
    ghcr.io/clickcaramel/polyglot-rocks:0.1.6
```

> Replace `<your_token>`, `<your_bundle_id>`, and `<path_to_project>` with your API token, product bundle identifier, and the path to your Xcode project, respectively.

**Keep in mind:** Docker uses absolute paths in volume mappings.

## License

**PolyglotRocks** is released under the Apache-2.0 license. See [LICENSE](./LICENSE) for details.
