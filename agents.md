# Agent Guidelines

## Testing Before Commits

All tests **must** pass before creating a commit. Run tests via Docker and verify there are no failures or compilation errors before committing changes.

## Running Flutter on aarch64 Linux with 16K Page Size Kernels

Flutter's Dart VM requires a 4K page size, which is incompatible with kernels configured for 16K pages (e.g. Fedora Asahi Linux on Apple Silicon). On these systems, Flutter cannot run natively.

Use Docker with an x86_64 Flutter image to run Flutter commands:

```bash
docker run --rm --platform linux/amd64 \
  -v /home/will/netmindz/WLED-Audio-Sender:/app \
  -w /app \
  ghcr.io/cirruslabs/flutter:stable \
  bash -c 'flutter pub get && flutter test'
```

On systems where Flutter runs natively (x86_64, or aarch64 with 4K pages), use `flutter` directly.
