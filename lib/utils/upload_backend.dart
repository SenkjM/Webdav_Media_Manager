// SPDX-License-Identifier: AGPL-3.0-or-later
import '../services/cloud_drive_service.dart';
import '../models/account_capabilities.dart';

/// 账号是否有上传能力（查 AccountCaps.write）。
bool accountCanUpload(String accountId, CloudDriveService cloudDrive) =>
    cloudDrive.can(accountId, AccountCaps.write);
