import '../l10n/generated/app_localizations.dart';

/// 云盘驱动族错误码 -> 本地化文案的统一出口。
///
/// 驱动与服务抛出的用户可见错误一律携带稳定码 err.xxx|detail（首个竖线
/// 之前是码，之后是动态值或上游文本，按原样透传）。没有码的历史文本
/// 按原文返回，升级前的数据仍可读。
class CloudDriverErrors {
  static final _errCode = RegExp(r'^err\.[a-zA-Z0-9]+');

  static final _invalidArgument = RegExp(
    r'^Invalid argument(\(s\))?( \([^)]+\))?: ',
  );

  static const _prefixes = [
    'Bad state: ',
    'WmpFormatException: ',
    'Unsupported operation: ',
    'Invalid argument(s): ',
  ];

  /// 把异常对象翻译成用户可读文案（走 [describe]）。
  static String describeException(Object error, AppLocalizations l10n) =>
      describe(error.toString(), l10n);

  static String describe(String raw, AppLocalizations l10n) {
    var text = raw;
    for (final prefix in _prefixes) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length);
        break;
      }
    }
    text = text.replaceFirst(_invalidArgument, '');

    final codeMatch = _errCode.firstMatch(text);
    if (codeMatch == null) return text;
    final code = codeMatch.group(0)!;
    var detail = text.substring(codeMatch.end);
    if (detail.startsWith('|')) detail = detail.substring(1);
    // CloudDriverException 的 cause 在 toString 里以全角括号附在码后，剥掉
    // 包装，让模板自带的分隔符（如「：」）直接衔接动态值。
    if (detail.length > 1 && detail.startsWith('（') && detail.endsWith('）')) {
      detail = detail.substring(1, detail.length - 1);
    }
    switch (code) {
      case 'err.accountNotConnected':
        return l10n.errAccountNotConnected(detail);
      case 'err.aliyunRefreshAllFailed':
        return l10n.errAliyunRefreshAllFailed(detail);
      case 'err.aliyunNonJson':
        return l10n.errAliyunNonJson(detail);
      case 'err.aliyunNoDriveId':
        return l10n.errAliyunNoDriveId;
      case 'err.aliyunNoDirectLink':
        return l10n.errAliyunNoDirectLink;
      case 'err.aliyunNetworkFailed':
        return l10n.errAliyunNetworkFailed(detail);
      case 'err.aliyunMissingRefreshToken':
        return l10n.errAliyunMissingRefreshToken;
      case 'err.aliyunEntryOrLinkFailed':
        return l10n.errAliyunEntryOrLinkFailed(detail);
      case 'err.baiduDirectLinkFailed':
        return l10n.errBaiduDirectLinkFailed(detail);
      case 'err.baiduRequestFailed':
        return l10n.errBaiduRequestFailed(detail);
      case 'err.baiduRiskControl':
        return l10n.errBaiduRiskControl(detail);
      case 'err.bigintOverflow':
        return l10n.errBigintOverflow(detail);
      case 'err.cloudAccountMissing':
        return l10n.errCloudAccountMissing(detail);
      case 'err.cloudWriteDisabled':
        return l10n.errCloudWriteDisabled;
      case 'err.contentRangeUnsupported':
        return l10n.errContentRangeUnsupported;
      case 'err.contentStreamUnsupported':
        return l10n.errContentStreamUnsupported;
      case 'err.cryptBadCipherLength':
        return l10n.errCryptBadCipherLength(detail);
      case 'err.cryptBlockDecryptFailed':
        return l10n.errCryptBlockDecryptFailed(detail);
      case 'err.cryptBlockRangeDecryptFailed':
        return l10n.errCryptBlockRangeDecryptFailed(detail);
      case 'err.cryptDecryptFailed':
        return l10n.errCryptDecryptFailed;
      case 'err.cryptEarlyEof':
        {
          final bar = detail.indexOf('|');
          final bar2 = bar > 0 ? detail.indexOf('|', bar + 1) : -1;
          return l10n.errCryptEarlyEof(
            bar > 0 ? detail.substring(0, bar) : detail,
            bar2 > 0 ? detail.substring(bar + 1, bar2) : '',
            bar2 > 0 ? detail.substring(bar2 + 1) : '',
          );
        }
      case 'err.cryptInvalidConfig':
        return l10n.errCryptInvalidConfig(detail);
      case 'err.cryptLengthMismatch':
        {
          final bar = detail.indexOf('|');
          return l10n.errCryptLengthMismatch(
            bar > 0 ? detail.substring(0, bar) : detail,
            bar > 0 ? detail.substring(bar + 1) : '',
          );
        }
      case 'err.cryptNoDirectLinkAnymore':
        return l10n.errCryptNoDirectLinkAnymore;
      case 'err.cryptNoDirectLinkDecrypt':
        return l10n.errCryptNoDirectLinkDecrypt;
      case 'err.cryptNoDirectLinkStream':
        return l10n.errCryptNoDirectLinkStream;
      case 'err.cryptNoHeader':
        return l10n.errCryptNoHeader;
      case 'err.cryptNoResponseBody':
        return l10n.errCryptNoResponseBody;
      case 'err.cryptNoSourceName':
        return l10n.errCryptNoSourceName;
      case 'err.cryptNotRcloneFile':
        return l10n.errCryptNotRcloneFile(detail);
      case 'err.cryptSizeUnknown':
        return l10n.errCryptSizeUnknown;
      case 'err.cryptSourceMissing':
        return l10n.errCryptSourceMissing(detail);
      case 'err.driverNotReady':
        return detail.isEmpty
            ? l10n.errDriverNotReady
            : l10n.errDriverNotReadyInfo(detail);
      case 'err.driverNotReadyInfo':
        return l10n.errDriverNotReadyInfo(detail);
      case 'err.driver123FileNotFound':
        return l10n.errDriver123FileNotFound(detail);
      case 'err.driver123NetworkFailed':
        return l10n.errDriver123NetworkFailed(detail);
      case 'err.driver123RequestFailed':
        return l10n.errDriver123RequestFailed(detail);
      case 'err.downloadSizeUnknown':
        return l10n.errDownloadSizeUnknown(detail);
      case 'err.missingRefreshToken':
        return l10n.errMissingRefreshToken;
      case 'err.mkdirRoot':
        return l10n.errMkdirRoot;
      case 'err.neteaseRootDelete':
        return l10n.errNeteaseRootDelete;
      case 'err.neteaseRequestFailed':
        return l10n.errNeteaseRequestFailed(detail);
      case 'err.neteaseRenameUnsupported':
        return l10n.errNeteaseRenameUnsupported;
      case 'err.neteaseNonJson':
        return l10n.errNeteaseNonJson(detail);
      case 'err.neteaseNoSongLink':
        return l10n.errNeteaseNoSongLink;
      case 'err.neteaseMoveUnsupported':
        return l10n.errNeteaseMoveUnsupported;
      case 'err.neteaseMkdirUnsupported':
        return l10n.errNeteaseMkdirUnsupported;
      case 'err.neteaseLoginExpired':
        return l10n.errNeteaseLoginExpired(detail);
      case 'err.neteaseFileNotFound':
        return l10n.errNeteaseFileNotFound(detail);
      case 'err.neteaseCopyUnsupported':
        return l10n.errNeteaseCopyUnsupported;
      case 'err.neteaseCookieRequired':
        return l10n.errNeteaseCookieRequired;
      case 'err.neteaseApiError':
        return l10n.errNeteaseApiError(detail);
      case 'err.neteaseRsaKeyLength':
        return l10n.errNeteaseRsaKeyLength;
      case 'err.neteaseUnknownCrypto':
        return l10n.errNeteaseUnknownCrypto(detail);
      case 'err.neteaseUnexpectedStructure':
        return l10n.errNeteaseUnexpectedStructure(detail);
      case 'err.open115TokenVerifyFailed':
        return l10n.errOpen115TokenVerifyFailed(detail);
      case 'err.open115RefreshFailed':
        return l10n.errOpen115RefreshFailed(detail);
      case 'err.open115NetworkFailed':
        return l10n.errOpen115NetworkFailed(detail);
      case 'err.open115NetworkConnectFailed':
        return l10n.errOpen115NetworkConnectFailed(detail);
      case 'err.open115MissingRefreshToken':
        return l10n.errOpen115MissingRefreshToken;
      case 'err.open115MissingPickCode':
        return l10n.errOpen115MissingPickCode(detail);
      case 'err.open115FolderNotFound':
        return l10n.errOpen115FolderNotFound(detail);
      case 'err.open115FileNotFound':
        return l10n.errOpen115FileNotFound(detail);
      case 'err.open115DownurlEmptyUrl':
        return l10n.errOpen115DownurlEmptyUrl;
      case 'err.open115DownurlEmptyData':
        return l10n.errOpen115DownurlEmptyData;
      case 'err.open115DirectLinkFailed':
        return l10n.errOpen115DirectLinkFailed(detail);
      case 'err.open115CopyRenameFailed':
        return l10n.errOpen115CopyRenameFailed(detail);
      case 'err.open115ApiError':
        return l10n.errOpen115ApiError(detail);
      case 'err.refreshOnlineFailed':
        {
          final bar = detail.indexOf('|');
          return l10n.errRefreshOnlineFailed(
            bar > 0 ? detail.substring(0, bar) : detail,
            bar > 0 ? detail.substring(bar + 1) : '',
          );
        }
      case 'err.refreshOnlineFailedNonJson':
        return l10n.errRefreshOnlineFailedNonJson(detail);
      case 'err.refreshOnlineNon200':
        return l10n.errRefreshOnlineNon200(detail);
      case 'err.rootOp':
        return l10n.errRootOp;
      case 'err.streamSizeUnknown':
        return l10n.errStreamSizeUnknown(detail);
      case 'err.teraboxSignKeyEmpty':
        return l10n.errTeraboxSignKeyEmpty;
      case 'err.teraboxRequestFailed':
        return l10n.errTeraboxRequestFailed(detail);
      case 'err.teraboxRedirectFailed':
        return l10n.errTeraboxRedirectFailed(detail);
      case 'err.unknownDriverType':
        return l10n.accountUnknownProvider(detail);
      case 'err.webdavNotConfigured':
        return l10n.errWebdavNotConfigured;
      case 'err.webdavSourceNotConnected':
        return l10n.errWebdavSourceNotConnected;
      case 'err.sourceUnbound':
        return l10n.dlErrSourceUnbound(detail);
      default:
        return text;
    }
  }
}
