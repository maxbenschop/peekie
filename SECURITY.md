# Security policy

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's private vulnerability reporting instead: open the **Security** tab of this repository and choose **Report a vulnerability**.

Include what you found, how to reproduce it and the Peekie and macOS versions involved. You can expect an acknowledgement within a few days. Once a fix is released, you will be credited unless you prefer otherwise.

## Things to know

- Peekie makes no network connections.
- With **Save notes between launches** on, notes are stored unencrypted in `~/Library/Application Support/Peekie/Notes`, readable by your user account.
- Quick capture needs the Accessibility permission. It only sends `⌘C` to the frontmost app and restores your clipboard afterwards.
- The adjustable blur reaches into internal Core Animation layers. It cannot access your data, but it may stop working on a future macOS version, in which case Peekie falls back to a plain fade.
