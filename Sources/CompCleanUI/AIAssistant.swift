import CleanerCore
import FoundationModels
import SwiftUI

/// Apple's on-device model, used only to explain what CompClean already decided.
/// Nothing leaves the Mac, and nothing it says changes what gets selected or removed.
@MainActor
final class AIAssistant: ObservableObject {
    @AppStorage("aiEnabled") var enabled = true {
        willSet { objectWillChange.send() }
    }

    /// Whether the model can run on this Mac right now (Apple Intelligence on, model downloaded).
    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    var isUsable: Bool { enabled && isAvailable }

    /// Why it can't run, in plain words, for Settings.
    var statusText: String {
        switch SystemLanguageModel.default.availability {
        case .available: "Ready. Runs on this Mac; nothing is sent anywhere."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in System Settings to use this."
        case .unavailable(.deviceNotEligible): "This Mac doesn't support Apple Intelligence."
        case .unavailable(.modelNotReady): "Apple's model is still downloading. Try again later."
        case .unavailable: "Not available on this Mac."
        }
    }

    /// Streams an answer to a question about one item, growing as it's written.
    func ask(_ question: String, facts: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: AIFacts.instructions)
                    let prompt = "\(facts)\n\nQuestion: \(question)"
                    for try await partial in session.streamResponse(to: prompt) {
                        continuation.yield(AIFacts.cleanAnswer(partial.content))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One or two sentences about a finished scan, or nil if the model isn't usable or fails.
    func summarize(_ facts: String) async -> String? {
        guard isUsable else { return nil }
        do {
            let session = LanguageModelSession(instructions: AIFacts.instructions)
            let text = AIFacts.cleanAnswer(try await session.respond(to: "\(facts)\n\n\(AIFacts.summaryRequest)").content)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    /// Friendly text for model errors (like content the safety filter declined).
    static func message(for error: Error) -> String {
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .guardrailViolation, .refusal: return "Apple's model declined to answer that one."
            case .exceededContextWindowSize: return "That was too long for the model. Try a shorter question."
            default: break
            }
        }
        return "Couldn't get an answer right now."
    }
}

/// One-line note at the top of item lists, so people know the AI is there. Hidden when unavailable.
struct AIHint: View {
    @EnvironmentObject var ai: AIAssistant

    var body: some View {
        if ai.isUsable {
            Label {
                Text("**AI explanations are on.** Click **Ask** on any item to ask what it is or what happens if you remove it. Runs on this Mac only.")
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(.tint)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// The "Ask about this" box shown inside an expanded row.
struct AskPanel: View {
    @EnvironmentObject var ai: AIAssistant
    let facts: String
    @State private var question = ""
    @State private var answer = ""
    @State private var asking = false
    @State private var failure: String?

    private let suggestions = ["What is this?", "What happens if I remove it?", "Will I lose anything?"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { s in
                    Button(s) { send(s) }.buttonStyle(.glass).controlSize(.small).disabled(asking)
                }
            }
            HStack(spacing: 8) {
                TextField("Ask anything about this item…", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { send(question) }
                Button {
                    send(question)
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title3) }
                .buttonStyle(.borderless)
                .disabled(asking || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if asking && answer.isEmpty {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Thinking…").foregroundStyle(.secondary) }
                    .font(.callout)
            }
            if !answer.isEmpty || failure != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text(failure ?? answer).font(.callout).fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Label("AI explanation, written on this Mac. CompClean's safety label is what counts.",
                          systemImage: "sparkles")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func send(_ q: String) {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !asking else { return }
        question = ""
        answer = ""
        failure = nil
        asking = true
        Task {
            do {
                for try await text in ai.ask(q, facts: facts) { answer = text }
            } catch {
                failure = AIAssistant.message(for: error)
            }
            asking = false
        }
    }
}
