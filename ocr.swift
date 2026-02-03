import Foundation
import Vision
import Cocoa

// 1. Check arguments
guard CommandLine.arguments.count > 1 else {
    print("Error: Please provide image path")
    exit(1)
}

let imagePath = CommandLine.arguments[1]

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
request.recognitionLanguages = ["zh-Hans", "en-US"]

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
