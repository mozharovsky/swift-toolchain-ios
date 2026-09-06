import Foundation

/// Immutable source identity consumed by build preparation and provenance checks.
package struct UpstreamSource: Codable, Equatable, Sendable {
    /// Build configuration refers to this stable component identifier.
    package let name: String
    /// Source acquisition uses a public HTTPS repository without embedded credentials.
    package let repository: String
    /// A full Git object identity prevents branch movement from changing a build input.
    package let revision: String
    /// Release preparation uses this SPDX expression to locate required notices.
    package let license: String

    /// Configuration validation rejects mutable revisions before source acquisition is implemented.
    package func validate() throws(ToolchainError) {
        guard name.range(of: #"^[a-z][a-z0-9-]*$"#, options: .regularExpression) != nil else {
            throw .invalidConfiguration("Use a lowercase component identifier for \(name).")
        }
        guard revision.range(of: #"^[a-f0-9]{40}$"#, options: .regularExpression) != nil else {
            throw .invalidConfiguration("Pin \(name) to a full lowercase Git commit hash.")
        }
        guard let url = URLComponents(string: repository), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, !url.path.isEmpty else {
            throw .invalidConfiguration("Use a public HTTPS repository URL for \(name).")
        }
        guard !license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .invalidConfiguration("Record the upstream license for \(name).")
        }
    }
}
