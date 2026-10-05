# License note: bundling precompiled libsodium

This is a short factual note for maintainers, **not legal advice**. Cite the
license texts themselves.

## Project licenses involved

| Component | License (as shipped in-tree) | Location |
|---|---|---|
| WebDAV Media Manager (app) | **AGPL-3.0** | repo root `LICENSE` |
| `packages/openlist_crypt` (Dart port) | **AGPL-3.0** (+ upstream notices for rclone / base32768 / golang.org/x/crypto) | `packages/openlist_crypt/LICENSE`, `packages/openlist_crypt/NOTICE` |
| libsodium (native `.so`) | **ISC** | `packages/openlist_crypt/native/LICENSE.libsodium` (from upstream 1.0.20) |

## What the ISC text requires (verbatim gist)

From libsodium's ISC license:

> Permission to use, copy, modify, and/or distribute this software for any
> purpose with or without fee is hereby granted, provided that the above
> copyright notice and this permission notice appear in all copies.

So redistributing the precompiled `libsodium.so` is consistent with ISC when
the copyright + permission notice is preserved (this directory keeps
`LICENSE.libsodium`).

## AGPL-3.0 package and host app

Both the app and `openlist_crypt` are AGPL-3.0. The ISC notice obligation for
libsodium remains. Shipping the `.so` inside an AGPL package does **not** by
itself re-license libsodium as AGPL—the ISC terms still apply to that binary.
Keep conveying:

1. AGPL-3.0 for app and Dart sources (`LICENSE` / package `LICENSE`).
2. Upstream attributions in `packages/openlist_crypt/NOTICE`.
3. libsodium ISC notice (`native/LICENSE.libsodium`) alongside the binary.

## Notices to keep when shipping an APK that includes the `.so`

- Retain `LICENSE.libsodium` (or equivalent copyright + ISC permission text) in
  the source tree and in any source/binary distribution that includes the `.so`.
- Do not strip upstream copyright from the notice file.
- EME / name codecs are unaffected (no libsodium code there).

## Out of scope

Compatibility of AGPL network-copyleft duties with third-party app stores,
trademark questions, and patent claims are **not** assessed here. Re-read the
full AGPL-3.0 and ISC texts before a production release decision.
