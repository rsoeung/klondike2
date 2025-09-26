# klondike2

A new Flutter project.

## Formatting

The project uses `dart format` with a line length of 100 characters.

Configuration sources:
- `.editorconfig` (authoritative line_length)
- `.vscode/settings.json` (IDE alignment: format on save & dart.lineLength)
- `tool/format.sh` (wrapper script)

Usage:
```
./tool/format.sh         # format in-place
./tool/format.sh --check # check only (non-zero exit if changes needed)
```

Why CLI and IDE looked different before: VS Code's formatter plugin already respected an internal 80-col default and created manual wraps earlier. Raising the limit later doesn’t auto-unwrap; Dart formatter only wraps lines that exceed the limit, it seldom rejoins prior breaks. To reduce wrapping, manually join lines (or temporarily set a much smaller limit then restore, though that’s noisy) and run the formatter again.
