import SwiftUI

/// How the Focus mixes were chosen: what research supports so far, how strongly, and where to
/// read it. (The longer notes are in design/focus/RESEARCH.md.)
struct FocusScienceView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Finding {
        let title: String
        let evidence: Preset.Evidence
        let text: String
        let mixes: String
        let sources: [(String, String?)]   // a citation, and a link where there's an open one
    }

    private let findings: [Finding] = [
        Finding(title: "Steady sound beats changing sound", evidence: .strong,
                text: "What breaks focus most is sound you can't help following: nearby voices, lyrics, and sounds that keep changing, like ticking or typing. Steady sound distracts least, and it covers nearby voices. Pink noise and water both mask speech; lab studies favor water, one long office trial didn't.",
                mixes: "Quiet Car, Steady Rain, Reading Room",
                sources: [("Perham & Currie, 2014, Applied Cognitive Psychology", nil),
                          ("Hongisto et al., 2017, Frontiers in Psychology", "https://pmc.ncbi.nlm.nih.gov/articles/PMC5515102/")]),
        Finding(title: "Noise for a wandering mind", evidence: .some,
                text: "A 2024 review of 13 studies found white or pink noise gave a small lift to attention for people with ADHD or attention difficulties, and a small drop for everyone else. Try it if your mind wanders, and skip it if it doesn't help. No study has tested brown, green or grey noise yet.",
                mixes: "Restless Mind, Pink Noise, White Noise",
                sources: [("Nigg et al., 2024, Journal of the American Academy of Child and Adolescent Psychiatry", "https://pmc.ncbi.nlm.nih.gov/articles/PMC11283987/")]),
        Finding(title: "A pulse at beta rate", evidence: .early,
                text: "Music whose loudness pulsed quickly, in the beta range around 16 times a second, helped sustained attention most for listeners with more ADHD traits, and it showed in their brain activity. It's one study, by researchers working with a focus-music company. Beta Pulse puts the same pulse on pink noise, which the study didn't test: it played plain pink noise as a comparison.",
                mixes: "Beta Pulse",
                sources: [("Woods et al., 2024, Communications Biology", "https://doi.org/10.1038/s42003-024-07026-3")]),
        Finding(title: "Binaural beats", evidence: .mixed,
                text: "Two tones a few hertz apart, one in each ear, are heard as a beat. Beta beats (16 to 24 Hz) in pink noise improved vigilance over slow beats in a 1998 study, and 40 Hz beats narrowed attention in one small study. But a 2023 review found the brainwave \"entrainment\" they're said to cause shows up inconsistently. They need headphones.",
                mixes: "Beta Beats, Gamma Beats",
                sources: [("Lane et al., 1998, Physiology & Behavior", "https://pubmed.ncbi.nlm.nih.gov/9423966/"),
                          ("Colzato et al., 2017, Psychological Research", nil),
                          ("Garcia-Argibay et al., 2019, Psychological Research", "https://pubmed.ncbi.nlm.nih.gov/30073406/"),
                          ("Ingendoh et al., 2023, PLOS ONE", "https://pmc.ncbi.nlm.nih.gov/articles/PMC10198548/")]),
        Finding(title: "A café's buzz for creative work", evidence: .some,
                text: "A moderate hum of background noise, about 70 dB like a busy café, helped creative thinking compared with quiet, while loud noise (85 dB) hurt it. It's for brainstorming, not detail work.",
                mixes: "Coffee Shop",
                sources: [("Mehta, Zhu & Cheema, 2012, Journal of Consumer Research", "https://doi.org/10.1086/665048")]),
        Finding(title: "Nature sounds for a break", evidence: .some,
                text: "Listening to natural sounds restored attention in a lab study where city sounds didn't, and a review of many studies links natural sounds to better mood and less stress. Give it a few minutes between focus blocks.",
                mixes: "Green Break",
                sources: [("Van Hedger et al., 2019, Psychonomic Bulletin & Review", "https://doi.org/10.3758/s13423-018-1539-1"),
                          ("Buxton et al., 2021, PNAS", nil)]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sounds for focus")
                        .font(Theme.display(36))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).padding(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                Text("We built the Focus mixes from what research supports so far, and we say how strong the evidence is. It's a young field, and none of this is medical advice.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 10)

                ForEach(findings, id: \.title) { finding in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(finding.evidence.rawValue.uppercased())
                            .font(Theme.caps(10))
                            .tracking(1.2)
                            .foregroundStyle(Theme.muted)
                        Text(finding.title).font(Theme.body(20))
                        Text(finding.text)
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Mixes: \(finding.mixes)")
                            .font(Theme.label(11))
                            .foregroundStyle(Theme.muted)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(finding.sources, id: \.0) { source, link in
                                if let link, let url = URL(string: link) {
                                    Link(destination: url) {
                                        Text(source).underline().font(Theme.label(10.5)).multilineTextAlignment(.leading)
                                    }
                                    .foregroundStyle(Theme.secondary)
                                } else {
                                    Text(source).font(Theme.label(10.5)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 22)
                    .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
                    .padding(.top, 18)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Theme.text)
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
    }
}
