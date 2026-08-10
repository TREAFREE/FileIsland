# Contributing

Thank you for helping improve File Island.

## Issues and testing feedback

Bug reports, reproducible test cases, documentation corrections, and feature discussions are welcome through GitHub Issues. Before posting:

- remove private filenames, absolute paths, metadata, logs, and media;
- state the File Island and macOS versions;
- describe the input format without uploading confidential source files;
- confirm whether the behavior also occurs with a small synthetic fixture.

## Code contributions

External code pull requests are not accepted. File Island is source-available under the proprietary terms in [`LICENSE`](LICENSE), and the maintainer intends to preserve the option of changing distribution terms for future versions. A contribution agreement or other explicit relicensing policy has not been established. Opening the source does not authorize the project to relicense third-party contributions.

Until that policy exists, use an issue to propose changes. The maintainer may implement the idea independently. Documentation-only corrections may also be proposed through an issue.

## Development source of truth

[`DEVELOPMENT_SPEC.md`](DEVELOPMENT_SPEC.md) is the project's only development specification and source of truth. Changes must preserve local-only processing, safe output behavior, sandbox authorization, batch rollback, accessibility motion behavior, and third-party license traceability.
