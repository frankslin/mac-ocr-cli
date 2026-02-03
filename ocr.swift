import Foundation
import Vision
import Cocoa
import PDFKit

// 1. Parse arguments
let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    print("Error: Please provide image path")
    print("Usage: ocr_tool <image_path|pdf_path> [--langs <lang1,lang2,...>] [--page <n>] (--json | --pdf <out.pdf>)")
    exit(1)
}

var imagePath: String?
var recognitionLanguages = ["zh-Hans", "zh-Hant", "ja-JP", "en-US"]
var pageNumber: Int?
var outputPDFPath: String?
var outputJSON = false
var pdfScale: CGFloat = 3.0
var debugImagePath: String?

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
    if arg == "--page" || arg == "-p" {
        let nextIndex = i + 1
        guard nextIndex < args.count else {
            print("Error: Missing value for \(arg)")
            exit(1)
        }
        let raw = args[nextIndex]
        guard let n = Int(raw), n > 0 else {
            print("Error: Invalid page number \(raw)")
            exit(1)
        }
        pageNumber = n
        i += 2
        continue
    }
    if arg == "--pdf" {
        let nextIndex = i + 1
        guard nextIndex < args.count else {
            print("Error: Missing value for \(arg)")
            exit(1)
        }
        outputPDFPath = args[nextIndex]
        i += 2
        continue
    }
    if arg == "--scale" || arg == "-s" {
        let nextIndex = i + 1
        guard nextIndex < args.count else {
            print("Error: Missing value for \(arg)")
            exit(1)
        }
        let raw = args[nextIndex]
        guard let val = Double(raw), val > 0 else {
            print("Error: Invalid scale \(raw)")
            exit(1)
        }
        pdfScale = CGFloat(val)
        i += 2
        continue
    }
    if arg == "--debug-image" {
        let nextIndex = i + 1
        guard nextIndex < args.count else {
            print("Error: Missing value for \(arg)")
            exit(1)
        }
        debugImagePath = args[nextIndex]
        i += 2
        continue
    }
    if arg == "--json" {
        outputJSON = true
        i += 1
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
    print("Usage: ocr_tool <image_path|pdf_path> [--langs <lang1,lang2,...>] [--page <n>] (--json | --pdf <out.pdf>)")
    exit(1)
}

if (outputJSON && outputPDFPath != nil) || (!outputJSON && outputPDFPath == nil) {
    print("Error: Please choose exactly one output: --json or --pdf <out.pdf>")
    exit(1)
}

let isPDF = imagePath.lowercased().hasSuffix(".pdf")
let cgImage: CGImage
let pageSize: CGSize

if isPDF {
    guard let pageNumber = pageNumber else {
        print("Error: --page is required for PDF input")
        exit(1)
    }
    guard let pdfDoc = PDFDocument(url: URL(fileURLWithPath: imagePath)) else {
        print("Error: Cannot load PDF")
        exit(1)
    }
    let pageIndex = pageNumber - 1
    guard pageIndex >= 0, pageIndex < pdfDoc.pageCount, let page = pdfDoc.page(at: pageIndex) else {
        print("Error: Page out of range")
        exit(1)
    }

    let bounds = page.bounds(for: .mediaBox)
    pageSize = bounds.size

    let width = max(Int(bounds.width * pdfScale), 1)
    let height = max(Int(bounds.height * pdfScale), 1)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("Error: Cannot allocate bitmap")
        exit(1)
    }
    bitmap.size = bounds.size
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        print("Error: Cannot create graphics context")
        exit(1)
    }
    NSGraphicsContext.current = context
    context.cgContext.setFillColor(NSColor.white.cgColor)
    context.cgContext.fill(CGRect(origin: .zero, size: bounds.size))
    context.cgContext.saveGState()
    // PDF pages can have non-zero origin; translate so the page renders into the bitmap.
    context.cgContext.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
    page.draw(with: .mediaBox, to: context.cgContext)
    context.cgContext.restoreGState()
    NSGraphicsContext.restoreGraphicsState()

    guard let rendered = bitmap.cgImage else {
        print("Error: Cannot render PDF page")
        exit(1)
    }
    cgImage = rendered
} else {
    // 2. Load image
    guard let nsImage = NSImage(contentsOfFile: imagePath),
          let rendered = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Error: Cannot load image")
        exit(1)
    }
    cgImage = rendered
    pageSize = CGSize(width: cgImage.width, height: cgImage.height)
}

if let debugImagePath = debugImagePath {
    let rep = NSBitmapImageRep(cgImage: cgImage)
    if let pngData = rep.representation(using: .png, properties: [:]) {
        do {
            try pngData.write(to: URL(fileURLWithPath: debugImagePath))
        } catch {
            print("Error: Cannot write debug image")
            exit(1)
        }
    } else {
        print("Error: Cannot encode debug image")
        exit(1)
    }
}

// 3. Configure OCR request
var ocrResults: [[String: Any]] = []
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

    ocrResults = results
    if outputJSON {
        if let jsonData = try? JSONSerialization.data(withJSONObject: results, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
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

// 6. Optional: write searchable PDF with invisible text layer
if let outputPDFPath = outputPDFPath {
    var mediaBox = CGRect(origin: .zero, size: pageSize)
    guard let consumer = CGDataConsumer(url: URL(fileURLWithPath: outputPDFPath) as CFURL) else {
        print("Error: Cannot create PDF output")
        exit(1)
    }
    guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        print("Error: Cannot create PDF context")
        exit(1)
    }
    pdfContext.beginPDFPage(nil)
    pdfContext.draw(cgImage, in: mediaBox)

    pdfContext.setTextDrawingMode(.invisible)
    pdfContext.setFillColor(NSColor.black.cgColor)

    for item in ocrResults {
        guard
            let text = item["text"] as? String,
            let box = item["box"] as? [String: Any],
            let x = box["x"] as? CGFloat,
            let y = box["y"] as? CGFloat,
            let w = box["w"] as? CGFloat,
            let h = box["h"] as? CGFloat
        else {
            continue
        }

        let rect = CGRect(
            x: x * pageSize.width,
            y: y * pageSize.height,
            width: max(w * pageSize.width, 1),
            height: max(h * pageSize.height, 1)
        )

        let fontSize = max(rect.height, 1)
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)
        pdfContext.textPosition = CGPoint(x: rect.minX, y: rect.minY)
        CTLineDraw(line, pdfContext)
    }

    pdfContext.endPDFPage()
    pdfContext.closePDF()
}
