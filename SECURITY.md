# Security Policy

## Supported Versions

Only the latest release of MDViewer receives security fixes. Fixes are shipped as a new release; earlier versions are not patched.

| Version | Supported |
| ------- | --------- |
| Latest release ([Releases](https://github.com/Masakai/mdviewer/releases/latest)) | Yes |
| Earlier releases | No |

## Reporting a Vulnerability

Please report vulnerabilities privately through GitHub's private vulnerability reporting:

1. Open the [Security tab](https://github.com/Masakai/mdviewer/security) of this repository.
2. Click **Report a vulnerability** and fill in the form.

Do not open a public issue, pull request or discussion for a vulnerability that has not been fixed yet.

Please include:

- The MDViewer version (MDViewer > About MDViewer) and whether you use `MDViewer-Universal.zip` or `MDViewer-AppleSilicon.zip`
- Your macOS version
- Steps to reproduce, and a Markdown file that triggers the issue if there is one
- What an attacker could do with it

## What to Expect

MDViewer is maintained by one person, so responses are best effort:

- I aim to acknowledge a report within 7 days.
- Once the issue is confirmed, I will work on a fix and keep you updated in the advisory.
- After a release with the fix is out, I will publish the advisory and credit you in it and in the [changelog](CHANGELOG.md), unless you would rather not be named.

## Scope

In scope:

- Problems caused by opening or previewing an untrusted Markdown file, such as running script in the preview, reading local files, sending data over the network, or opening URLs or applications without the user's action
- The Quick Look extension
- Code signing and notarization of the released builds

Out of scope:

- Vulnerabilities in the bundled libraries themselves (marked, DOMPurify, Shiki, KaTeX, Mermaid); please report those to their maintainers. Issues where the way MDViewer uses a library makes it exploitable are in scope.
- Issues that require an attacker to modify the app bundle or already control the user's account

## Known Limitations

These are current design decisions, not vulnerabilities:

- The main app does not use App Sandbox. The Quick Look extension is sandboxed.
- Clicking a `file:` link in the preview opens that file with its default application, in the same way as double-clicking it in Finder. Links with schemes other than `http`, `https`, `mailto` and `file` are not opened.
