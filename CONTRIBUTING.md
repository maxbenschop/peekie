# Contributing to Peekie

Thanks for wanting to help. Peekie is a small project, so contributing is simple: open an issue or a pull request.

## Before you start

- **Bugs and small fixes:** open a pull request directly.
- **New features or behaviour changes:** open an issue first so we can agree on the approach before you spend time on it.
- **Questions:** open a discussion or an issue. There are no silly ones.

Peekie is guided by a few principles. Changes that fit them are much easier to accept:

- **Native and small.** AppKit and SwiftUI only, no third-party dependencies.
- **Private by default.** No network access, no telemetry, nothing stored unless the person opts in.
- **Follows the Human Interface Guidelines.** Standard controls, system fonts, the system materials, and a proper macOS look and feel.
- **Fast and out of the way.** It should open instantly and never get in the person's way.

## Setting up

You need macOS 14 or later and Xcode 26 or later.

```sh
git clone https://github.com/<your-username>/peekie.git
cd peekie
open Peekie.xcodeproj
```

Or build and install from the command line:

```sh
./scripts/install.sh
```

Two things worth knowing while you develop:

- **Accessibility permission.** Quick capture needs it. macOS ties the grant to the code signature, so if you have an Apple Development certificate installed, `install.sh` uses it and the permission survives rebuilds. Without one, the app is signed ad hoc and you must grant it again after each rebuild.
- **No Dock icon.** Peekie runs as an accessory app. Launch it again from Applications to open Settings, where `⌘Q` quits it.

## Running the tests

```sh
./scripts/test.sh logic
./scripts/test.sh editor
./scripts/test.sh window
./scripts/test.sh all
```

- `logic` covers maths, code highlighting, export and saved notes. It needs no window and runs quickly.
- `editor` drives the text view: typing, lists, checkboxes, formatting, colours and images.
- `window` opens real note windows to test blur, keep on top, saving and restoring, show and hide, click away and image sizing. It needs a normal desktop session, and it takes a couple of minutes.

The tests run in their own process with a temporary folder and their own settings, so they never touch your real notes or preferences. Please add or update a test with any change to behaviour. The suites live in `Tests/`.

## Code style

- Follow the style of the surrounding code. Swift, four-space indentation, no trailing whitespace.
- **Prefer clear names over comments.** The code has no explanatory comments on purpose. If something needs explaining because it is genuinely non-obvious, such as a platform quirk, write it in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) rather than in the source.
- Keep views small and put logic in plain types that can be tested.
- Do not add dependencies.
- Match the macOS text styles and standard control sizes from the HIG instead of inventing spacing.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make your change, with tests.
3. Run `./scripts/test.sh all` and make sure the app builds with `xcodebuild -project Peekie.xcodeproj -scheme Peekie -configuration Release build`.
4. Open a pull request and fill in the template. A screenshot or short recording helps a lot for anything visual.

Write commit messages in the imperative mood ("Fix image size on restore", not "Fixed"). Keep pull requests focused: one change per pull request is easier to review and easier to revert.

## Reporting bugs

Open an issue with the bug report template. Include your macOS version, your Mac type and the Peekie version (open the Peekie menu while Settings is open and choose **About Peekie**). Steps to reproduce matter most.

## Security

Please report security problems privately. See [SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
