# Security

Report vulnerabilities through the repository's private security advisory channel when it is
available. Avoid publishing exploit details or credentials in ordinary issues. Private reporting is
a GitHub repository setting and must be enabled by the maintainer separately.

Compiler and SDK inputs must have immutable identities. Keep release credentials separate from pull
request checks. Untrusted changes must not execute on a maintainer's workstation or receive release
secrets. Review changes to workflows, build downloads, and artifact manifests as code execution paths.

Native compiler execution occurs inside its consumer's process. Report memory corruption, arbitrary
file access, unexpected native code loading, and unsafe artifact extraction as security issues.
An experimental artifact has no implied production support guarantee.
