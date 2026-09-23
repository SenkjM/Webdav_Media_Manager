/// 流式音乐页的播放模式。控制条最左边的按钮在三个值之间轮换。
///
/// 只影响**流式**播放：本地播放走各自的播放器与队列语义，不读这个值。
/// 值与模式本身一起存进设置，下次进流式页仍是上次那个。
enum MusicStreamPlayMode {
  /// 单曲循环：一首放完从头再来。
  single,

  /// 顺序：一首接一首往下走，到队尾停住。
  sequential,

  /// 列表循环：到队尾回到第一首。
  loop,
}

extension MusicStreamPlayModeX on MusicStreamPlayMode {
  String get storageKey => switch (this) {
    MusicStreamPlayMode.single => 'single',
    MusicStreamPlayMode.sequential => 'sequential',
    MusicStreamPlayMode.loop => 'loop',
  };

  /// 按钮上的短文案（按钮本身只有图标，文案走 tooltip 与提示）。
  String get labelZh => switch (this) {
    MusicStreamPlayMode.single => '单曲循环',
    MusicStreamPlayMode.sequential => '顺序播放',
    MusicStreamPlayMode.loop => '列表循环',
  };

  /// 按一次切到下一个模式。顺序是默认值，所以轮换顺序是
  /// 顺序 → 列表循环 → 单曲循环 → 顺序。
  MusicStreamPlayMode get next => switch (this) {
    MusicStreamPlayMode.sequential => MusicStreamPlayMode.loop,
    MusicStreamPlayMode.loop => MusicStreamPlayMode.single,
    MusicStreamPlayMode.single => MusicStreamPlayMode.sequential,
  };

  static MusicStreamPlayMode fromStorageKey(String? key) {
    switch (key) {
      case 'single':
        return MusicStreamPlayMode.single;
      case 'loop':
        return MusicStreamPlayMode.loop;
      case 'sequential':
      default:
        return MusicStreamPlayMode.sequential;
    }
  }
}
