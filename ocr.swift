import Foundation
import Vision
import Cocoa
import PDFKit
import ImageIO
import UniformTypeIdentifiers

// 1. Parse arguments
let args = Array(CommandLine.arguments.dropFirst())

let buildCommit = "__GIT_COMMIT_VALUE__"
let projectURL = "https://github.com/frankslin/mac-ocr-cli"
let authorName = "Frank Lin"
let toolSignature: String = {
    let commit = (buildCommit == "__GIT_COMMIT_VALUE__") ? "unknown" : buildCommit
    return "mac-ocr-cli \(projectURL) by \(authorName) (commit \(commit))"
}()

let helpText = """
Usage: ocr_tool [--help] [--version] [--list-revisions] <image_path|pdf_path> [--langs <lang1,lang2,...>] [--page <n>] [--scale <factor>] [--debug-image <path>] [--revision <n>] [--bilevel] [--ccitt-g4] (--json | --pdf <out.pdf>)

Options:
  --help, -h             Show this help and exit.
  --version, -v          Show build commit ID and exit.
  --list-revisions       Print supported recognition revisions and exit (macOS 12+).
  --langs, -l            Comma-separated language list (default: zh-Hans,zh-Hant,ja-JP,en-US).
  --page, -p             1-based page number for PDF input (required for PDF).
  --scale, -s            PDF render scale factor (default: 3).
  --debug-image          Write rendered page image to a PNG for inspection.
  --bilevel              Force 1-bit bilevel image when writing PDF (for smaller size).
  --ccitt-g4             Use libtiff+tiff2pdf for CCITT G4 PDF, then overlay text with qpdf.
  --revision, -r         Vision recognition revision (defaults to latest supported).
  --json                 Output JSON only.
  --pdf                  Output searchable PDF with invisible text layer.
"""

if args.contains("--help") || args.contains("-h") {
    print(helpText)
    exit(0)
}

if args.contains("--version") || args.contains("-v") {
    if buildCommit == "__GIT_COMMIT_VALUE__" {
        print("unknown")
    } else {
        print(buildCommit)
    }
    exit(0)
}

guard !args.isEmpty else {
    print("Error: Please provide image path")
    print(helpText)
    exit(1)
}

var imagePath: String?
var recognitionLanguages = ["zh-Hans", "zh-Hant", "ja-JP", "en-US"]
var pageNumber: Int?
var outputPDFPath: String?
var outputJSON = false
var pdfScale: CGFloat = 3.0
var debugImagePath: String?
var recognitionRevision: Int?
var listRevisions = false
var forceBilevel = false
var useCcittG4 = false

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
    if arg == "--bilevel" {
        forceBilevel = true
        i += 1
        continue
    }
    if arg == "--ccitt-g4" {
        useCcittG4 = true
        i += 1
        continue
    }
    if arg == "--revision" || arg == "-r" {
        let nextIndex = i + 1
        guard nextIndex < args.count else {
            print("Error: Missing value for \(arg)")
            exit(1)
        }
        let raw = args[nextIndex]
        guard let val = Int(raw), val > 0 else {
            print("Error: Invalid revision \(raw)")
            exit(1)
        }
        recognitionRevision = val
        i += 2
        continue
    }
    if arg == "--list-revisions" {
        listRevisions = true
        i += 1
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

if listRevisions {
    if #available(macOS 12.0, *) {
        let probe = VNRecognizeTextRequest()
        probe.recognitionLevel = .accurate
        probe.recognitionLanguages = recognitionLanguages
        probe.usesLanguageCorrection = true
        let supported = collectSupportedRevisions(using: probe)
        let list = supported.sorted().map(String.init).joined(separator: ",")
        print(list)
        exit(0)
    } else {
        print("Error: --list-revisions requires macOS 12+")
        exit(1)
    }
}

guard let imagePath = imagePath else {
    print("Error: Please provide image path")
    print(helpText)
    exit(1)
}

if (outputJSON && outputPDFPath != nil) || (!outputJSON && outputPDFPath == nil) {
    print("Error: Please choose exactly one output: --json or --pdf <out.pdf>")
    exit(1)
}
if useCcittG4 && outputPDFPath == nil {
    print("Error: --ccitt-g4 requires --pdf output")
    exit(1)
}

let isPDF = imagePath.lowercased().hasSuffix(".pdf")
let cgImage: CGImage
let pageSize: CGSize

func isBilevel(_ image: CGImage) -> Bool {
    return image.bitsPerComponent == 1 &&
        image.bitsPerPixel == 1 &&
        image.colorSpace?.model == .monochrome &&
        image.alphaInfo == .none
}

func makeBilevelImage(_ image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    let graySpace = CGColorSpaceCreateDeviceGray()

    // First render into 8-bit grayscale
    let bytesPerRow8 = width
    guard let grayContext = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow8,
        space: graySpace,
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else {
        return nil
    }
    grayContext.interpolationQuality = .none
    grayContext.setShouldAntialias(false)
    grayContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let grayData = grayContext.data else {
        return nil
    }

    // Then threshold into 1-bit buffer
    let outBytesPerRow = (width + 7) / 8
    let outSize = outBytesPerRow * height
    let outData = UnsafeMutablePointer<UInt8>.allocate(capacity: outSize)
    outData.initialize(repeating: 0, count: outSize)

    let threshold: UInt8 = 128
    for y in 0..<height {
        let row8 = grayData.advanced(by: y * bytesPerRow8).assumingMemoryBound(to: UInt8.self)
        let rowOut = outData.advanced(by: y * outBytesPerRow)
        for x in 0..<width {
            let v = row8[x]
            if v >= threshold {
                rowOut[x >> 3] |= (0x80 >> (x & 7))
            }
        }
    }

    let releaseCallback: CGDataProviderReleaseDataCallback = { _, data, _ in
        data.assumingMemoryBound(to: UInt8.self).deallocate()
    }
    guard let provider = CGDataProvider(
        dataInfo: nil,
        data: outData,
        size: outSize,
        releaseData: releaseCallback
    ) else {
        outData.deallocate()
        return nil
    }

    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 1,
        bitsPerPixel: 1,
        bytesPerRow: outBytesPerRow,
        space: graySpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}

func writeTIFF(image: CGImage, to url: URL, dpi: Double) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil) else {
        return false
    }
    let tiffProps: [CFString: Any] = [
        kCGImagePropertyTIFFCompression: 1,
        kCGImagePropertyTIFFXResolution: dpi,
        kCGImagePropertyTIFFYResolution: dpi,
        kCGImagePropertyTIFFResolutionUnit: 2,
        kCGImagePropertyTIFFPhotometricInterpretation: 1
    ]
    CGImageDestinationAddImage(destination, image, tiffProps as CFDictionary)
    return CGImageDestinationFinalize(destination)
}

@discardableResult
func runProcess(_ launchPath: String, _ arguments: [String]) -> Int32 {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchPath)
    task.arguments = arguments
    do {
        try task.run()
    } catch {
        return -1
    }
    task.waitUntilExit()
    return task.terminationStatus
}

func drawTextLayer(_ context: CGContext, pageSize: CGSize, results: [[String: Any]]) {
    context.setTextDrawingMode(.invisible)
    context.setFillColor(NSColor.black.cgColor)

    for item in results {
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
        context.textPosition = CGPoint(x: rect.minX, y: rect.minY)
        CTLineDraw(line, context)
    }
}

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

// Recognition revision (use latest supported if not specified)
func collectSupportedRevisions(using template: VNRecognizeTextRequest) -> [Int] {
    var revisions: [Int] = []
    let candidates = [1, 2, 3, 4]

    if #available(macOS 12.0, *) {
        for rev in candidates {
            let probe = VNRecognizeTextRequest()
            probe.recognitionLevel = template.recognitionLevel
            probe.recognitionLanguages = template.recognitionLanguages
            probe.usesLanguageCorrection = template.usesLanguageCorrection
            probe.revision = rev
            if let _ = try? probe.supportedRecognitionLanguages() {
                revisions.append(rev)
            }
        }
    }

    return revisions
}

let supportedRevisions = collectSupportedRevisions(using: request)
if let recognitionRevision = recognitionRevision {
    if supportedRevisions.contains(recognitionRevision) {
        request.revision = recognitionRevision
    } else {
        print("Error: Unsupported recognition revision \(recognitionRevision)")
        exit(1)
    }
} else if let latest = supportedRevisions.max() {
    request.revision = latest
}

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
    if useCcittG4 {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            print("Error: Cannot create temp directory")
            exit(1)
        }
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        guard let bilevelImage = makeBilevelImage(cgImage) else {
            print("Error: Cannot create bilevel image for CCITT G4")
            exit(1)
        }
        let inputTIFF = tempDir.appendingPathComponent("input.tif")
        let g4TIFF = tempDir.appendingPathComponent("g4.tif")
        let basePDF = tempDir.appendingPathComponent("base.pdf")
        let textPDF = tempDir.appendingPathComponent("text.pdf")

        let dpi: Double = isPDF ? (72.0 * Double(pdfScale)) : 72.0
        if !writeTIFF(image: bilevelImage, to: inputTIFF, dpi: dpi) {
            print("Error: Cannot write temporary TIFF")
            exit(1)
        }

        let rows = max(bilevelImage.height, 1)
        let tiffcpStatus = runProcess("/opt/homebrew/bin/tiffcp", [
            "-c", "g4", "-s", "-r", "\(rows)",
            inputTIFF.path, g4TIFF.path
        ])
        if tiffcpStatus != 0 {
            print("Error: tiffcp failed")
            exit(1)
        }

        let tiff2pdfStatus = runProcess("/opt/homebrew/bin/tiff2pdf", [
            "-o", basePDF.path,
            "-c", toolSignature,
            "-t", "mac-ocr-cli",
            "-x", "\(dpi)",
            "-y", "\(dpi)",
            g4TIFF.path
        ])
        if tiff2pdfStatus != 0 {
            print("Error: tiff2pdf failed")
            exit(1)
        }

        // Create text-only PDF
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextCreator: toolSignature,
            kCGPDFContextTitle: "mac-ocr-cli"
        ]
        guard let consumer = CGDataConsumer(url: textPDF as CFURL) else {
            print("Error: Cannot create text PDF output")
            exit(1)
        }
        guard let textContext = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else {
            print("Error: Cannot create text PDF context")
            exit(1)
        }
        textContext.beginPDFPage(nil)
        drawTextLayer(textContext, pageSize: pageSize, results: ocrResults)
        textContext.endPDFPage()
        textContext.closePDF()

        let qpdfStatus = runProcess("/opt/homebrew/bin/qpdf", [
            basePDF.path,
            "--overlay", textPDF.path, "--",
            outputPDFPath
        ])
        if qpdfStatus != 0 {
            print("Error: qpdf overlay failed")
            exit(1)
        }
    } else {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextCreator: toolSignature,
            kCGPDFContextTitle: "mac-ocr-cli"
        ]
        guard let consumer = CGDataConsumer(url: URL(fileURLWithPath: outputPDFPath) as CFURL) else {
            print("Error: Cannot create PDF output")
            exit(1)
        }
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else {
            print("Error: Cannot create PDF context")
            exit(1)
        }
        pdfContext.beginPDFPage(nil)
        var imageForPDF = cgImage
        if forceBilevel, let bilevel = makeBilevelImage(cgImage) {
            imageForPDF = bilevel
            pdfContext.setShouldAntialias(false)
            pdfContext.interpolationQuality = .none
        } else if isBilevel(cgImage) {
            pdfContext.setShouldAntialias(false)
            pdfContext.interpolationQuality = .none
        } else if cgImage.colorSpace?.model == .monochrome, cgImage.alphaInfo == .none,
                  let bilevel = makeBilevelImage(cgImage) {
            imageForPDF = bilevel
            pdfContext.setShouldAntialias(false)
            pdfContext.interpolationQuality = .none
        }
        pdfContext.draw(imageForPDF, in: mediaBox)

        drawTextLayer(pdfContext, pageSize: pageSize, results: ocrResults)
        pdfContext.endPDFPage()
        pdfContext.closePDF()
    }
}
