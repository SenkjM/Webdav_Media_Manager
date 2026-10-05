# License note: bundling precompiled libsodium

This is a short factual note for maintainers, **not legal advice**. Cite the
license texts themselves.

## Project licenses involved

| Component | License (as shipped in-tree) | Location |
|---|---|---|
| WebDAV Media Manager (app) | **AGPL-3.0** | repo root `LICENSE` |
| `packages/openlist_crypt` (Dart port) | **MIT** (+ notices for rclone / base32768 / golang.org/x/crypto) | `packages/openlist_crypt/LICENSE` |
| libsodium (native `.so`) | **ISC** | `packages/openlist_crypt/native/LICENSE.libsodium` (from upstream 1.0.20) |

## What the ISC text requires (verbatim gist)

From libsodium's ISC license:

> Permission to use, copy, modify, and/or distribute this software for any
> purpose with or without fee is hereby granted, provided that the above
> copyright notice and this permission notice appear in all copies.

So redistributing the precompiled `libsodium.so` is consistent with ISC when
the copyright + permission notice is preserved (this directory keeps
`LICENSE.libsodium`).

## AGPL-3.0 host app

AGPL-3.0 allows combining with other works; the ISC notice obligation for
libsodium remains. Shipping the `.so` inside an AGPL app does **not** by itself
re-license libsodium as AGPL—the ISC terms still apply to that binary, and the
app remains AGPL for its own code. Keep conveying both:

1. App AGPL-3.0 (`LICENSE` at repo root / distribution notices the project already uses).
2. libsodium ISC notice (`native/LICENSE.libsodium`) alongside the binary.

## openlist_crypt MIT package

The Dart package license is MIT. Adding an optional ISC-covered native binary
under `native/` does not remove MIT obligations for the Dart sources; document
the extra ISC file when distributing the package with the `.so`.

## Notices to keep when shipping an APK that includes the `.so`

- Retain `LICENSE.libsodium` (or equivalent copyright + ISC permission text) in
  the source tree and in any source/binary distribution that includes the `.so`.
- Do not strip upstream copyright from the notice file.
- EME / name codecs are unaffected (no libsodium code there).

## Out of scope

Compatibility of AGPL network-copyleft duties with third-party app stores,
trademark questions, and patent claims are **not** assessed here. Re-read the
full AGPL-3.0 and ISC texts before a production release decision.
