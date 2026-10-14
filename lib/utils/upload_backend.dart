// SPDX-License-Identifier: AGPL-3.0-or-later
import '../services/webdav_service.dart';
import '../models/account_capabilities.dart';

/// 账号是否有上传能力（查 AccountCaps.write）。
bool accountCanUpload(String accountId, WebDavService webDav) =>
    webDav.can(accountId, AccountCaps.write);
