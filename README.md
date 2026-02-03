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
./ocr_tool /path/to/image.png --json
./ocr_tool /path/to/image.png --langs zh-Hans,zh-Hant,ja-JP,en-US --json
./ocr_tool /path/to/input.pdf --page 1 --pdf /path/to/output.pdf
./ocr_tool /path/to/input.pdf --page 1 --json --scale 4
./ocr_tool /path/to/input.pdf --page 1 --json --scale 4 --debug-image /tmp/page1.png
```

The output is JSON:

```json
[{"text":"...","confidence":0.98,"box":{"x":0.1,"y":0.2,"w":0.3,"h":0.4}}]
```

## Notes

- Coordinates are Vision’s normalized bounding boxes (origin at bottom-left).
- Default recognition languages: Simplified Chinese, Traditional Chinese, Japanese, and English.
- Override with `--langs` or `-l` using a comma-separated list (e.g. `zh-Hans,ja-JP`).
- PDF input requires `--page <n>` (1-based).
- Use `--scale <factor>` to render PDF pages at higher resolution (default `3`).
- Use `--debug-image <path>` to write the rendered page image for inspection.
- Choose exactly one output mode: `--json` or `--pdf <out.pdf>`.
- Use `--pdf <out.pdf>` to write a searchable PDF with an invisible text layer.
- Recognition level is set to `accurate`.

## License

MIT
