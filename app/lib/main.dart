// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Phase 1 MVP entry point. Boots the local store (SQLite, WAL), seeds the
// local shop/user identity, and gates everything behind the mandatory
// first-run acknowledgment (spec §0.4).

import 'dart:io';

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:faultcorral_store/faultcorral_store.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/acknowledgment_screen.dart';
import 'src/app_state.dart';
import 'src/project_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final database =
      FaultCorralDatabase.open('${supportDir.path}/faultcorral.db');
  final store = FaultCorralStore(database);
  runApp(FaultCorralApp(state: bootstrapState(store)));
}

/// Seeds the single local shop/user on first launch. Extracted for tests.
AppState bootstrapState(FaultCorralStore store) {
  const shopId = 'shop-local';
  const userId = 'user-local';
  var shop = store.getShop(shopId);
  if (shop == null) {
    shop = Shop(
      meta: newMeta('shop', userId),
      name: 'My Shop',
      subscriptionTier: SubscriptionTier.free,
    );
    shop = Shop(
      meta: EntityMeta(
          id: shopId,
          createdAt: shop.meta.createdAt,
          updatedAt: shop.meta.updatedAt,
          createdBy: userId),
      name: shop.name,
      subscriptionTier: shop.subscriptionTier,
      settings: shop.settings,
    );
    store.saveShop(shop, by: userId);
  }
  var user = store.getUser(userId);
  if (user == null) {
    final now = DateTime.now().toUtc();
    user = User(
      meta: EntityMeta(
          id: userId, createdAt: now, updatedAt: now, createdBy: userId),
      shopId: shopId,
      displayName: Platform.environment['USER'] ?? 'Local User',
      role: UserRole.owner,
    );
    store.saveUser(user, by: userId);
  }
  return AppState(store: store, shop: shop, user: user);
}

class FaultCorralApp extends StatefulWidget {
  const FaultCorralApp({super.key, required this.state});

  final AppState state;

  @override
  State<FaultCorralApp> createState() => _FaultCorralAppState();
}

class _FaultCorralAppState extends State<FaultCorralApp> {
  late bool _needsAcknowledgment;

  @override
  void initState() {
    super.initState();
    _needsAcknowledgment = widget.state.store.needsAcknowledgment(
        widget.state.user.meta.id, acknowledgmentTextVersion);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaultCorral',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6D4C2F),
        useMaterial3: true,
      ),
      home: _needsAcknowledgment
          ? AcknowledgmentScreen(
              gate: const AcknowledgmentGate(
                  currentTextVersion: acknowledgmentTextVersion),
              onAccepted: (record) {
                widget.state.store.recordAcknowledgment(record);
                setState(() => _needsAcknowledgment = false);
              },
            )
          : ProjectListScreen(state: widget.state),
    );
  }
}
