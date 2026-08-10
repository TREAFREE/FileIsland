# Security Policy

## Supported versions

Security fixes are provided for the latest published File Island release. Early-access builds are ad-hoc signed and are not notarized by Apple; verify every downloaded artifact against the SHA-256 file attached to the same GitHub Release.

## Reporting a vulnerability

Use the repository's **Security → Report a vulnerability** private reporting flow. Please include:

- the affected File Island version and macOS version;
- reproducible steps and observed impact;
- whether a crafted file, filename, folder structure, or symbolic link is involved;
- logs with private paths and media content removed.

Do not open a public issue for an unpatched vulnerability and do not upload private source media. If GitHub private vulnerability reporting is temporarily unavailable, open a public issue containing no vulnerability details and ask the maintainer to provide a private contact channel.

The maintainer will acknowledge a complete report as capacity allows. This volunteer project does not currently promise a fixed response or remediation SLA.

## Release authenticity

The `v0.1.0` early-access release is not Developer ID signed or notarized. The official download location is the repository's [GitHub Releases](https://github.com/TREAFREE/FileIsland/releases) page. Never install a copy whose checksum differs from the `.sha256` attachment.
