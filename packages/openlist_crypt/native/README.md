# Native libsodium (optional secretbox backend)

Precompiled **libsodium** shared library used only by
`packages/openlist_crypt` content secretbox (`crypto_secretbox_easy` /
`crypto_secretbox_open_easy`). Filename EME / name codecs stay pure Dart.

## Shipped binary

| Item | Value |
|---|---|
| Path | `android/arm64-v8a/libsodium.so` |
| Upstream | [jedisct1/libsodium](https://github.com/jedisct1/libsodium) **1.0.20** |
| Source tarball | https://download.libsodium.org/libsodium/releases/libsodium-1.0.20.tar.gz |
| Build | Official `dist-build/android-armv8-a.sh` with Android NDK **r27c**, `LIBSODIUM_FULL_BUILD=Y`, `NDK_PLATFORM=android-21` |
| Target | `armv8-a+crypto` → Android ABI folder `arm64-v8a` |
| SHA-256 | `704a03b241bd54bae071e1d2b43261bfbae1fbd87fdac296bcbb7712d10ee97e` |

Only **arm64-v8a** is vendored in this experiment (sandbox / OnePlus). Other
ABIs fall back to the Dart secretbox path when the `.so` is missing.

## How the app loads it

The host app adds this directory as an Android `jniLibs` source (see
`android/app/build.gradle.kts`). At runtime Dart opens `libsodium.so` via
`dart:ffi`. Override path with env `OPENLIST_CRYPT_LIBSODIUM_PATH`. Prefer the
native engine with `preferLibsodiumSecretbox()` or
`--dart-define=OPENLIST_CRYPT_LIBSODIUM=true`.

## Rebuild

```sh
export ANDROID_NDK_HOME=/path/to/android-ndk-r27c
tar xzf libsodium-1.0.20.tar.gz && cd libsodium-1.0.20
export LIBSODIUM_FULL_BUILD=Y
./dist-build/android-armv8-a.sh
cp libsodium-android-armv8-a+crypto/lib/libsodium.so \
  /path/to/openlist_crypt/native/android/arm64-v8a/libsodium.so
```

## License notices

See [LICENSE.libsodium](LICENSE.libsodium) (ISC) and
[LICENSE_NOTE.md](LICENSE_NOTE.md). Keep the ISC copyright notice with any
redistribution of the binary.
