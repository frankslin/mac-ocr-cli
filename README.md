# mac-ocr-cli

A minimal macOS OCR command-line tool written in Swift, using Apple’s Vision framework. It compiles as a single Swift file and outputs JSON with recognized text and bounding boxes.

## Requirements

- macOS with Vision framework support
- Xcode Command Line Tools (for `swiftc`)
- Optional for `--ccitt-g4`: `libtiff` (`tiffcp`, `tiff2pdf`) and `qpdf`

## Build

```bash
swiftc ocr.swift -o ocr_tool
```

## CI Build

The GitHub Actions workflow builds a `universal2` binary on macOS and uploads it as an artifact:

```bash
ocr_tool-universal2
```

## Usage

```bash
./ocr_tool --list-revisions
./ocr_tool --help
./ocr_tool -h
./ocr_tool --version
./ocr_tool -v
./ocr_tool /path/to/image.png --json
./ocr_tool /path/to/image.png --langs zh-Hans,zh-Hant,ja-JP,en-US --json
./ocr_tool /path/to/input.pdf --page 1 --pdf /path/to/output.pdf
./ocr_tool /path/to/input.pdf --page 1 --json --scale 4
./ocr_tool /path/to/input.pdf --page 1 --json --scale 4 --debug-image /tmp/page1.png
./ocr_tool /path/to/image.png --json --revision 3
./ocr_tool /path/to/input.pdf --page 1 --pdf /path/to/output.pdf --ccitt-g4
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
- Use `--bilevel` to force 1-bit output when writing PDF (smaller files).
- Use `--ccitt-g4` to generate a CCITT G4 PDF via libtiff (`tiffcp`, `tiff2pdf`) and overlay text with `qpdf`.
- Use `--revision <n>` to select a Vision recognition revision (defaults to latest supported).
- Use `--list-revisions` to print supported recognition revisions and exit (macOS 12+).
- Use `--help` or `-h` to show all options.
- Use `--version` or `-v` to show the build commit ID.

### Embed Commit ID

To compile with the current git commit ID embedded:

```bash
./scripts/build.sh
```
- Choose exactly one output mode: `--json` or `--pdf <out.pdf>`.
- Use `--pdf <out.pdf>` to write a searchable PDF with an invisible text layer.
- Recognition level is set to `accurate`.
- PDF metadata includes the tool name and commit ID (when embedded).
- If the input image is monochrome (black/white) it will be converted to 1-bit and written without interpolation to favor CCITT G4 compression.

## License

MIT
