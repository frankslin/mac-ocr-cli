import Foundation
import Vision
import Cocoa

// 1. Parse arguments
let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    print("Error: Please provide image path")
    print("Usage: ocr_tool <image_path> [--langs <lang1,lang2,...>]")
    exit(1)
}

var imagePath: String?
var recognitionLanguages = ["zh-Hans", "zh-Hant", "ja-JP", "en-US"]

var i = 0
while i < args.count {
    let arg = args[i]
    if arg == "--langs" || arg == "-l" {
        let nextIndex = i + 1
        guard nextIndex < args.count else {
            print("Error: Missing value for \(arg)")
            exit(1)
        }
        let raw = args[nextIndex]
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let langs = parts.filter { !$0.isEmpty }.map { String($0) }
        if langs.isEmpty {
            print("Error: Empty language list")
            exit(1)
        }
        recognitionLanguages = langs
        i += 2
        continue
    }

    if arg.hasPrefix("-") {
        print("Error: Unknown option \(arg)")
        exit(1)
    }

    if imagePath == nil {
        imagePath = arg
    } else {
        print("Error: Unexpected extra argument \(arg)")
        exit(1)
    }
    i += 1
}

guard let imagePath = imagePath else {
    print("Error: Please provide image path")
    print("Usage: ocr_tool <image_path> [--langs <lang1,lang2,...>]")
    exit(1)
}

// 2. Load image
guard let nsImage = NSImage(contentsOfFile: imagePath),
      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Error: Cannot load image")
    exit(1)
}

// 3. Configure OCR request
let request = VNRecognizeTextRequest { request, error in
    if let error = error {
        print("Error: \(error)")
        return
    }

    guard let observations = request.results as? [VNRecognizedTextObservation] else {
        return
    }

    let results: [[String: Any]] = observations.compactMap { observation in
        guard let candidate = observation.topCandidates(1).first else {
            return nil
        }

        let boundingBox = observation.boundingBox

        return [
            "text": candidate.string,
            "confidence": candidate.confidence,
            "box": [
                "x": boundingBox.origin.x,
                "y": boundingBox.origin.y,
                "w": boundingBox.size.width,
                "h": boundingBox.size.height
            ]
        ]
    }

    if let jsonData = try? JSONSerialization.data(withJSONObject: results, options: []),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        print(jsonString)
    }
}

// Set recognition level (accurate for best, fast for speed)
request.recognitionLevel = .accurate

// Supported languages (auto-detect or specify)
request.recognitionLanguages = recognitionLanguages

// Use language correction
request.usesLanguageCorrection = true

// 5. Perform request
let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

do {
    try handler.perform([request])
} catch {
    print("Error: \(error)")
    exit(1)
}
