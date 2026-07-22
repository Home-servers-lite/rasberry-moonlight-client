# Vendored Cloudsmith Files

These files are kept in the repository so the installer does not execute a remote `curl | bash` setup script.

## Files

- `setup.deb.sh`
  - Original Cloudsmith-generated setup script for `moonlight-game-streaming/moonlight-qt`.
  - Kept for audit/provenance.
  - Not executed by `scripts/setup-moonlight-pi.sh`.
  - SHA256: `f309187cea9dd45cd36f542e38cd84d415d5c1ef8972a8a2b9d49cdecb3d84a3`

- `gpg.2F6AE14E1C660D44.key`
  - Cloudsmith repository public signing key.
  - Used locally by `scripts/setup-moonlight-pi.sh` to create `/usr/share/keyrings/moonlight-game-streaming-moonlight-qt-archive-keyring.gpg`.
  - SHA256: `e3015be2637545f6aae825032c5d4e02b65f5b6d32010cbd4eab2cc4744d3dac`

## Source URLs

- https://dl.cloudsmith.io/public/moonlight-game-streaming/moonlight-qt/setup.deb.sh
- https://dl.cloudsmith.io/public/moonlight-game-streaming/moonlight-qt/gpg.2F6AE14E1C660D44.key
- https://dl.cloudsmith.io/public/moonlight-game-streaming/moonlight-qt/deb/raspbian

The installer still uses apt to download signed Moonlight packages from the Cloudsmith repository. It does not download or execute Cloudsmith setup scripts at runtime.
