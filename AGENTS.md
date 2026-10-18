# Store-edition development boundaries

- This is an isolated public-source prototype. Do not install or launch the GUI on the owner's current Mac/Edge or modify the installed personal edition without a new explicit deployment request.
- Consumer USB/wireless handover is a required release gate, not an optional feature to silently remove. USB accessory SDK/IOKit compilation and offline fixtures are not real hardware verification. No HDC/debug-mode requirement in the consumer product.
- Use actual panel/window geometry and hardware codec capabilities; model catalog entries are documentation/geometry fixtures, not certified-device claims.
- Use the official SDK. Keep the personal tablet/easyGo descriptor only as a reference until a distributable, officially valid input configuration has been tested. Do not patch a global SDK.
- This variant rejects public remote-control sessions and does not link an audio/microphone provider. Do not silently reintroduce private WAN runtimes, elevated system services, shared pairing tokens or a microphone permission.
- Keep genuine pairing credentials, signing certificates, profiles, account data and raw user/device diagnostics out of public Git. Do not import the personal private repository's Git objects into this public repository.
- Public source visibility has been authorized. A project-owned general reuse license has not been selected; do not change that grant without the owner's instruction. Preserve third-party license notices.
- Every delivered source/build needs a commit, immutable version tag, notes, SHA-256 manifest and cloud re-download verification. All GitHub network traffic must use a verified PQJC path with no TAG fallback.
- Never claim AppGallery approval, notarization, Windows support, minimum-OS certification, real streaming performance or perfect multi-device compatibility from compilation/fixtures alone.
