# OpenAPI Generator

Generate objects and paths from an OpenAPI schema.

<details>
<summary>Why does this exist?</summary>

This initially started as a fork of [CreateAPI](https://github.com/CreateAPI/CreateAPI), which I have contributed to and used greatly. You'll notice that the configuration options and output are very similar. I just needed to extend the project where I needed to, as well as trying out using swift-synax for a lot of the code generation instead of entirely manually making the files.

**Why not [`swift-openapi-generator`](https://github.com/apple/swift-openapi-generator)?**

Because it's absolutely horrendous to setup and use. All I want is the objects and paths from a schema along with a lightweight HTTP layer that I was already using.

**Why named `openapi-generator`?**

Because naming things is hard.

</details>

## Install

Add to your package:

```swift
dependencies: [
    .package(url: "https://github.com/LePips/openapi-generator.git", branch: "main"),
]
```

## Configure

Customize generation with a configuration file with many available options.

See [CONFIGURATION](CONFIGURATION.md) for all options.

```yaml
module: MyAPI

comments:
  options:
    - description

entities:
  conformances:
    - Codable
    - Sendable
  enumConformances:
    - Codable
    - CaseIterable
    - Sendable
  exclude:
    - SomeType.internalProperty

paths:
  namespace: API
  filenameTemplate: "%0API.swift"
  inlineQueryParameterLimit: null
```

## Generate

Run the plugin from your package:

```sh
swift package plugin --allow-writing-to-package-directory generate-openapi \
  ./openapi.json \
  --config openapi-generator.yml \
  --output Sources/MyAPI/Generated
```

Generated `Paths` use [`Get`](https://github.com/kean/Get) by default, so add it to your runtime target if you generate paths.
