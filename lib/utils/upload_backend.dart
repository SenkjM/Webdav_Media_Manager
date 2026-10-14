// SPDX-License-Identifier: AGPL-3.0-or-later
import '../models/account_capabilities.dart';

/// Whether this backend can receive an uploaded file.
///
/// Cloud drives have no upload primitive. A write bit on a non-WebDAV account
/// is not enough: packing a CBZ and then calling writeFromFile fails with
/// err.cloudWriteDisabled. Callers pass the mask from
/// CloudDriveService.capabilitiesFor, which already applies the WebDAV stored
/// bits or the driver table.
bool accountCanUpload({
  required String providerType,
  required int capabilities,
}) {
  if (providerType != 'webdav') return false;
  return AccountCaps.has(capabilities, AccountCaps.write);
}
