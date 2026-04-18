# Agent Guidelines

## Testing Before Commits

All tests **must** pass before creating a commit. Run `flutter test` and verify there are no failures or compilation errors before committing changes.

## Running Flutter on aarch64 Linux with 16K Page Size Kernels

Flutter's Dart VM requires a 4K page size, which is incompatible with kernels configured for 16K pages (e.g. Fedora Asahi Linux on Apple Silicon). On these systems, Flutter cannot run natively.

Use the `muvm-flutter.sh` wrapper script to run Flutter commands inside a microVM (muvm) that provides a 4K page size environment:

```bash
./muvm-flutter.sh test                  # run tests
./muvm-flutter.sh build apk --debug     # build APK
./muvm-flutter.sh pub get               # get dependencies
./muvm-flutter.sh analyze               # run analysis
./muvm-flutter.sh <any flutter args>    # pass-through
```

The wrapper automatically installs Flutter inside the VM on first use. The installation persists across runs since muvm shares the host filesystem.

On systems where Flutter runs natively (x86_64, or aarch64 with 4K pages), use `flutter` directly.
