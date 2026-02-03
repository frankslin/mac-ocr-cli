# mac-ocr-cli

A minimal macOS OCR command-line tool written in Swift, using Apple’s Vision framework. It compiles as a single Swift file and outputs JSON with recognized text and bounding boxes.

## Requirements

- macOS with Vision framework support
- Xcode Command Line Tools (for `swiftc`)

## Build

```bash
swiftc ocr.swift -o ocr_tool
```

## Usage

```bash
./ocr_tool /path/to/image.png
```

The output is JSON:

```json
[{"text":"...","confidence":0.98,"box":{"x":0.1,"y":0.2,"w":0.3,"h":0.4}}]
```

## Notes

- Coordinates are Vision’s normalized bounding boxes (origin at bottom-left).
- Default recognition languages: Simplified Chinese and English.
- Recognition level is set to `accurate`.

## License

MIT
