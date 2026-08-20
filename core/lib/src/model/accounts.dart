// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import 'common.dart';

/// Subscription state of a shop (spec §1: free tier = 1 active project,
/// no PDF export; paid = unlimited). Gating mechanics land in Phase 2.
enum SubscriptionTier {
  free('free'),
  paid('paid');

  const SubscriptionTier(this.wire);
  final String wire;

  static SubscriptionTier fromWire(String wire) =>
      SubscriptionTier.values.firstWhere((v) => v.wire == wire);
}

/// Shop-level settings (spec §2.1).
@immutable
class ShopSettings {
  const ShopSettings({
    this.defaultVoltageSystem,
    this.reportBrandingRef,
    this.legalFooterOverride,
  });

  final VoltageSystem? defaultVoltageSystem;

  /// Reference to logo/branding asset managed by the app layer.
  final String? reportBrandingRef;

  /// Shop-supplied additions to the report footer. Never replaces the
  /// mandatory disclaimer block (spec §6.4).
  final String? legalFooterOverride;

  Map<String, Object?> toJson() => {
        'default_voltage_system': defaultVoltageSystem?.wire,
        'report_branding_ref': reportBrandingRef,
        'legal_footer_override': legalFooterOverride,
      };

  factory ShopSettings.fromJson(Map<String, Object?> json) => ShopSettings(
        defaultVoltageSystem: json['default_voltage_system'] == null
            ? null
            : VoltageSystem.fromWire(json['default_voltage_system'] as String),
        reportBrandingRef: json['report_branding_ref'] as String?,
        legalFooterOverride: json['legal_footer_override'] as String?,
      );
}

/// Account root (spec §2.1).
@immutable
class Shop {
  const Shop({
    required this.meta,
    required this.name,
    required this.subscriptionTier,
    this.settings = const ShopSettings(),
  });

  final EntityMeta meta;
  final String name;
  final SubscriptionTier subscriptionTier;
  final ShopSettings settings;

  Map<String, Object?> toJson() => {
        ...meta.toJson(),
        'name': name,
        'subscription_tier': subscriptionTier.wire,
        'settings': settings.toJson(),
      };

  factory Shop.fromJson(Map<String, Object?> json) => Shop(
        meta: EntityMeta.fromJson(json),
        name: json['name'] as String,
        subscriptionTier:
            SubscriptionTier.fromWire(json['subscription_tier'] as String),
        settings: ShopSettings.fromJson(
            (json['settings'] as Map).cast<String, Object?>()),
      );
}

enum UserRole {
  owner('owner'),
  editor('editor'),
  viewer('viewer');

  const UserRole(this.wire);
  final String wire;

  static UserRole fromWire(String wire) =>
      UserRole.values.firstWhere((v) => v.wire == wire);
}

/// Member of a shop (spec §2.1).
@immutable
class User {
  const User({
    required this.meta,
    required this.shopId,
    required this.displayName,
    required this.role,
    this.email,
  });

  final EntityMeta meta;
  final Id shopId;
  final String displayName;
  final UserRole role;
  final String? email;

  Map<String, Object?> toJson() => {
        ...meta.toJson(),
        'shop_id': shopId,
        'display_name': displayName,
        'role': role.wire,
        'email': email,
      };

  factory User.fromJson(Map<String, Object?> json) => User(
        meta: EntityMeta.fromJson(json),
        shopId: json['shop_id'] as Id,
        displayName: json['display_name'] as String,
        role: UserRole.fromWire(json['role'] as String),
        email: json['email'] as String?,
      );
}
