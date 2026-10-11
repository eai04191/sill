import MarkdownUI
import SwiftUI

struct ChangelogPopup: View {
    private var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.0.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("v\(bundleVersion) Changelog")
                .padding(15)
                .font(.system(size: 14))
                .fontWeight(.medium)
            Rectangle().fill(Color.primary).opacity(0.2).frame(height: 0.5)
            ScrollView {
                Markdown(Self.changelogText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 20)
                    .padding(.trailing, 15)
                    .markdownTheme(.barik)
            }.offset(x: 15)
                .markdownImageProvider(WebImageProvider())
        }
        .scrollIndicators(.hidden)
        .frame(width: 500)
        .frame(maxHeight: 600)
    }

    /// The section of this version in the CHANGELOG.md bundled with the app, read once per launch. The bundled file
    /// is the changelog of the source the app was built from, so it has this build's own changes and needs no network.
    private static let changelogText: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
            let fullChangelog = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "Failed to load CHANGELOG."
        }
        let extractedSection = extractSection(forVersion: version, from: fullChangelog)
        return extractedSection.isEmpty ? "Changelog for v\(version) not found" : extractedSection
    }()

    // Extracts the section corresponding to the specified version from the changelog
    private static func extractSection(
        forVersion version: String, from changelog: String
    ) -> String {
        let lines = changelog.components(separatedBy: .newlines)

        // Match the whole heading, so 0.5.1 does not find the section of 0.5.10 or 0.5.1-beta.
        guard
            let versionIndex = lines.firstIndex(where: {
                $0.hasPrefix("## ") && $0.dropFirst(3).trimmingCharacters(in: .whitespaces) == version
            })
        else {
            return ""
        }

        var sectionLines: [String] = []
        for i in versionIndex..<lines.count {
            let line = lines[i]

            if i == versionIndex, line.hasPrefix("## ") {
                continue
            }

            // End the section when a new version header is encountered
            if i != versionIndex && line.hasPrefix("## ") {
                break
            }

            // Replace "<br>" with a markdown header if encountered
            if line == "<br>" {
                sectionLines.append("### ")
            } else {
                sectionLines.append(line)
            }
        }

        return sectionLines.joined(separator: "\n")
    }
}

// MARK: - Preview

struct ChangelogPopup_Previews: PreviewProvider {
    static var previews: some View {
        ChangelogPopup()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
