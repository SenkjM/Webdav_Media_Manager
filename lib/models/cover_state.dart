/// Persisted cover availability state for a library row.
///
/// Replaces the old persisted local cover **path** as the authority. The local
/// thumb file is always derived from identity (music: `identityHashStem`;
/// manga: `manga_cover_stem(id)`), so only the *state* needs to be persisted.
///
/// Encoding matches Core (`wdmm-storage` schema v10): a small integer in
/// SQLite / JSON FFI.
///
/// | value | state    | meaning                          | fill cache |
/// |-------|----------|----------------------------------|------------|
/// | 0     | unknown  | not probed                       | allowed    |
/// | 1     | none     | probed, no art                   | forbidden  |
/// | 2     | present  | source has art / we saved bytes  | allowed    |
///
/// Call sites gate fill (`none` skip; `present`/`unknown` may fill) **before**
/// invoking the shared thin ensure helper.
enum CoverState {
  unknown(0),
  none(1),
  present(2);

  const CoverState(this.value);

  /// The integer persisted in SQLite / JSON FFI.
  final int value;

  /// Decode the integer Core/FFI form. Any out-of-range or null value maps to
  /// [unknown] (the safe default that still allows a fill attempt).
  static CoverState fromInt(int? v) => switch (v) {
    1 => CoverState.none,
    2 => CoverState.present,
    _ => CoverState.unknown,
  };
}
