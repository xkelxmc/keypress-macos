import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct AboutSettingsPane: View {
    @Environment(\.studioStrings) private var strings
    @State private var diagnosticsDocument = DiagnosticsDocument(contents: "")
    @State private var isExportingDiagnostics = false
    @State private var diagnosticsExportError: String?

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private var latestReleaseNotes: [AboutReleaseNote] {
        [
            AboutReleaseNote(
                titleKey: "about.release21.ribbon.title",
                bodyKey: "about.release21.ribbon.body",
                systemImage: "text.append",
                tint: .orange),
            AboutReleaseNote(
                titleKey: "about.release21.echo.title",
                bodyKey: "about.release21.echo.body",
                systemImage: "text.cursor",
                tint: .purple),
            AboutReleaseNote(
                titleKey: "about.release21.command.title",
                bodyKey: "about.release21.command.body",
                systemImage: "command",
                tint: .blue),
            AboutReleaseNote(
                titleKey: "about.release21.motion.title",
                bodyKey: "about.release21.motion.body",
                systemImage: "wand.and.stars",
                tint: .pink),
        ]
    }

    private var highlightNotes: [AboutReleaseNote] {
        [
            AboutReleaseNote(
                titleKey: "about.release.cursor.title",
                bodyKey: "about.release.cursor.body",
                systemImage: "cursorarrow.motionlines",
                tint: .cyan),
            AboutReleaseNote(
                titleKey: "about.release.position.title",
                bodyKey: "about.release.position.body",
                systemImage: "arrow.up.and.down.and.arrow.left.and.right",
                tint: .blue),
            AboutReleaseNote(
                titleKey: "about.release.studio.title",
                bodyKey: "about.release.studio.body",
                systemImage: "sidebar.left",
                tint: .indigo),
            AboutReleaseNote(
                titleKey: "about.release.history.title",
                bodyKey: "about.release.history.body",
                systemImage: "list.bullet.rectangle",
                tint: .purple),
            AboutReleaseNote(
                titleKey: "about.release.displays.title",
                bodyKey: "about.release.displays.body",
                systemImage: "display.2",
                tint: .teal),
            AboutReleaseNote(
                titleKey: "about.release.reliability.title",
                bodyKey: "about.release.reliability.body",
                systemImage: "checkmark.shield.fill",
                tint: .green),
        ]
    }

    var body: some View {
        StudioPage(
            titleKey: "about.title",
            subtitleKey: "about.product.subtitle")
        {
            StudioCard {
                VStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 92, height: 92)
                        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
                        .accessibilityHidden(true)

                    HStack(spacing: 10) {
                        Text("Keypress")
                            .font(.system(size: 28, weight: .bold))

                        Text(self.version)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Color.primary.opacity(0.06),
                                in: Capsule())
                    }

                    Text(self.strings["about.product.description"])
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 540)

                    Text(
                        String(
                            format: self.strings["about.version"],
                            self.version,
                            self.build))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            StudioCard("about.onboarding.title", systemImage: "play.circle.fill", tint: .purple) {
                HStack(spacing: 18) {
                    Text(self.strings["about.onboarding.body"])
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)

                    Button {
                        OnboardingController.shared.replay()
                    } label: {
                        Label(
                            self.strings["about.onboarding.action"],
                            systemImage: "sparkles")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(Color.accentColor.gradient, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(StudioHoverButtonStyle(showsHoverSurface: false))
                }
            }

            StudioCard("about.release21.title", systemImage: "sparkles", tint: .indigo) {
                AboutReleaseNoteGrid(notes: self.latestReleaseNotes)
            }

            StudioCard("about.highlights.title", systemImage: "star.fill", tint: .yellow) {
                AboutReleaseNoteGrid(notes: self.highlightNotes)

                StudioDivider()

                AboutExternalLinkRow(
                    title: self.strings["about.release.all"],
                    detail: "GitHub Releases",
                    systemImage: "clock.arrow.circlepath",
                    tint: .indigo,
                    url: URL(string: "https://github.com/xkelxmc/keypress-macos/releases")!)
            }

            StudioCard("about.privacy", systemImage: "hand.raised.fill", tint: .blue) {
                Text(self.strings["about.privacy.detail"])
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                StudioDivider()

                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.blue)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(
                            Color.blue.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)

                    Text(self.strings["about.diagnostics.detail"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)

                    Button(self.strings["about.diagnostics.export"]) {
                        self.exportDiagnostics()
                    }
                }
            }

            StudioCard("about.links", systemImage: "link", tint: .indigo) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250), spacing: 10)],
                    alignment: .leading,
                    spacing: 10)
                {
                    AboutExternalLinkRow(
                        title: self.strings["about.link.website"],
                        detail: "showkeypress.com",
                        systemImage: "globe",
                        tint: .blue,
                        url: URL(string: "https://showkeypress.com")!)

                    AboutExternalLinkRow(
                        title: self.strings["about.link.creator"],
                        detail: "github.com/xkelxmc",
                        systemImage: "person.crop.circle.fill",
                        tint: .indigo,
                        url: URL(string: "https://github.com/xkelxmc")!)

                    AboutExternalLinkRow(
                        title: self.strings["about.link.community"],
                        detail: "GitHub Discussions",
                        systemImage: "bubble.left.and.bubble.right.fill",
                        tint: .purple,
                        url: URL(string: "https://github.com/xkelxmc/keypress-macos/discussions")!)

                    AboutExternalLinkRow(
                        title: self.strings["about.link.issue"],
                        detail: "GitHub Issues",
                        systemImage: "ladybug.fill",
                        tint: .orange,
                        url: URL(string: "https://github.com/xkelxmc/keypress-macos/issues/new/choose")!)
                }
            }

            Text(self.strings["about.copyright"])
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
        .fileExporter(
            isPresented: self.$isExportingDiagnostics,
            document: self.diagnosticsDocument,
            contentType: .plainText,
            defaultFilename: DiagnosticsReport.suggestedFilename)
        { result in
            if case let .failure(error) = result {
                self.diagnosticsExportError = error.localizedDescription
            }
        }
        .alert(
                self.strings["about.diagnostics.failed"],
                isPresented: Binding(
                    get: { self.diagnosticsExportError != nil },
                    set: { isPresented in
                        if !isPresented {
                            self.diagnosticsExportError = nil
                        }
                    })) {
                Button(self.strings["action.done"]) {
                    self.diagnosticsExportError = nil
                }
            } message: {
                Text(self.diagnosticsExportError ?? "")
            }
    }

    private func exportDiagnostics() {
        self.diagnosticsDocument = DiagnosticsDocument(contents: DiagnosticsReport.make())
        self.isExportingDiagnostics = true
    }
}

private struct DiagnosticsDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]

    let contents: String

    init(contents: String) {
        self.contents = contents
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let contents = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.contents = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(self.contents.utf8))
    }
}

private struct AboutReleaseNote: Identifiable {
    let titleKey: String
    let bodyKey: String
    let systemImage: String
    let tint: Color

    var id: String {
        self.titleKey
    }
}

private struct AboutReleaseNoteGrid: View {
    let notes: [AboutReleaseNote]

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 275), spacing: 24, alignment: .topLeading),
                GridItem(.flexible(minimum: 275), spacing: 24, alignment: .topLeading),
            ],
            alignment: .leading,
            spacing: 16)
        {
            ForEach(self.notes) { note in
                AboutReleaseNoteRow(note: note)
            }
        }
    }
}

private struct AboutReleaseNoteRow: View {
    @Environment(\.studioStrings) private var strings
    let note: AboutReleaseNote

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: self.note.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(self.note.tint)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    self.note.tint.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.strings[self.note.titleKey])
                    .font(.subheadline.weight(.semibold))
                Text(self.strings[self.note.bodyKey])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct AboutExternalLinkRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(self.url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: self.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(self.tint)
                    .frame(width: 28, height: 28)
                    .background(
                        self.tint.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(self.title)
                        .foregroundStyle(.primary)
                    Text(self.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
