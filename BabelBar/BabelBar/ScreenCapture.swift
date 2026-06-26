import AppKit
import Vision

enum ScreenCapture {

    /// All languages we can OCR (matches the supported translation languages).
    static let supportedRecognitionLanguages = ["en-US", "ru-RU", "de-DE", "es-ES", "fr-FR", "it-IT", "pt-PT"]

    /// Launches the system interactive region capture (`screencapture -i`),
    /// then runs Vision OCR on the captured image and returns recognized text.
    /// `languages` is a priority-ordered list of BCP-47 codes (first = highest priority).
    static func captureAndRecognize(languages: [String] = supportedRecognitionLanguages) async -> String? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("babelbar_\(UUID().uuidString).png")

        let ok = await runScreencapture(to: tmp)
        guard ok, let image = NSImage(contentsOf: tmp),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            try? FileManager.default.removeItem(at: tmp)
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        return await recognizeText(in: cg, languages: languages)
    }

    private static func runScreencapture(to url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", url.path]
            process.terminationHandler = { p in
                continuation.resume(returning: p.terminationStatus == 0
                                    && FileManager.default.fileExists(atPath: url.path))
            }
            do { try process.run() } catch { continuation.resume(returning: false) }
        }
    }

    private static func recognizeText(in cg: CGImage, languages: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.isEmpty ? nil : lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Keep only languages this Vision revision actually supports (avoids a throw).
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            let usable = languages.filter { supported.contains($0) }
            request.recognitionLanguages = usable.isEmpty ? ["en-US"] : usable

            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }
}
