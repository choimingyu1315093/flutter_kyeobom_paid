import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

abstract final class KyeobomSubscriptionProducts {
  // Create these as SUBSCRIPTIONS in Play Console for com.mingyu.kyeobom.
  // Prices are always fetched from Google Play, never hard-coded.
  static const monthly = 'kyeobom_premium_monthly';
  static const yearly = 'kyeobom_premium_yearly';
  static const ids = {monthly, yearly};
}

abstract final class KyeobomPremiumEntitlement {
  /// UI state only. Privileged feature access must ALSO be checked by the
  /// server / Firestore security rules, not by this client-side value alone.
  static bool active(Map<String, dynamic>? data, {DateTime? now}) {
    if (data?['source'] != 'google_play' || data?['isActive'] != true) {
      return false;
    }
    final expiry = data?['expiresAt'];
    if (expiry is! Timestamp) return false;
    return expiry.toDate().isAfter(now ?? DateTime.now());
  }
}

/// Google Play Billing and Firebase server verification.
/// Never unlock on a local purchase callback without server confirmation.
class KyeobomBillingController extends ChangeNotifier {
  KyeobomBillingController({
    InAppPurchase? store,
    FirebaseFunctions? functions,
  }) : _store = store ?? InAppPurchase.instance,
       _functions = functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  final InAppPurchase _store;
  final FirebaseFunctions _functions;
  StreamSubscription<List<PurchaseDetails>>? _purchaseListener;

  List<ProductDetails> products = [];
  String status = '구독 상품을 확인하고 있어요.';
  bool loading = true;
  bool storeAvailable = false;
  bool purchaseInProgress = false;
  bool premium = false;
  bool _closed = false;

  bool get canPurchase =>
      Platform.isAndroid && storeAvailable && !purchaseInProgress;

  void _refresh() {
    if (!_closed) notifyListeners();
  }

  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      loading = false;
      status = 'iPhone 구독 결제는 준비 중입니다. Android에서 먼저 제공해요.';
      _refresh();
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      loading = false;
      status = '구독은 뷰어 이메일 계정으로 로그인한 후 이용할 수 있어요.';
      _refresh();
      return;
    }

    // Attach before requesting products or purchases so resumed transactions
    // are never missed when the widget opens.
    _purchaseListener = _store.purchaseStream.listen(
      (batch) => unawaited(_handlePurchases(batch)),
      onError: (Object error) {
        status = 'Google Play 구매 확인 오류: $error';
        purchaseInProgress = false;
        _refresh();
      },
    );
    try {
      storeAvailable = await _store.isAvailable();
      if (!storeAvailable) {
        status = 'Google Play 스토어에 연결할 수 없습니다.';
        return;
      }
      final result = await _store.queryProductDetails(
        KyeobomSubscriptionProducts.ids,
      );
      products = result.productDetails.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      if (result.notFoundIDs.isNotEmpty) {
        status = 'Play Console 구독 상품이 아직 조회되지 않았어요: ' +
            result.notFoundIDs.join(', ');
      } else {
        status = products.isEmpty
          ? '등록된 구독 상품이 없습니다.'
          : '원하는 구독 상품을 선택해 주세요.';
      }
      await refreshEntitlement();
    } catch (error) {
      status = '구독 상품 확인 오류: $error';
    } finally {
      loading = false;
      _refresh();
    }
  }

  Future<void> refreshEntitlement() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || !Platform.isAndroid) {
      premium = false;
      _refresh();
      return;
    }
    // Server revalidates Google Play purchase state. If Cloud Functions
    // are not deployed, keep premium locked rather than trusting local state.
    final result = await _functions
        .httpsCallable('refreshKyeobomSubscription')
        .call<Map<String, dynamic>>({});
    premium = result.data['premium'] == true;
    _refresh();
  }

  Future<void> buy(ProductDetails product) async {
    if (!canPurchase || !KyeobomSubscriptionProducts.ids.contains(product.id)) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      status = '뷰어 이메일 계정 로그인이 필요합니다.';
      _refresh();
      return;
    }
    purchaseInProgress = true;
    status = 'Google Play 결제 창을 여는 중이에요.';
    _refresh();
    try {
      // This SHA-256 ID is independently checked against Google's signed
      // subscription data on the server.
      final obfuscatedUid = sha256.convert(utf8.encode(user.uid)).toString();
      final param = GooglePlayPurchaseParam(
        productDetails: product,
        applicationUserName: obfuscatedUid,
      );
      await _store.buyNonConsumable(purchaseParam: param);
    } catch (error) {
      purchaseInProgress = false;
      status = 'Google Play 결제 창을 열지 못했어요: $error';
      _refresh();
    }
  }

  Future<void> restore() async {
    if (!Platform.isAndroid || !storeAvailable) return;
    status = '기존 Google Play 구매 내역을 확인하고 있어요.';
    _refresh();
    try {
      await _store.restorePurchases();
    } catch (error) {
      status = '구매 복원 오류: $error';
      _refresh();
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> batch) async {
    for (final purchase in batch) {
      if (!KyeobomSubscriptionProducts.ids.contains(purchase.productID)) {
        continue;
      }
      if (purchase.status == PurchaseStatus.pending) {
        purchaseInProgress = true;
        status = '결제 승인 대기 중이에요. 승인 후 다시 확인해 주세요.';
        _refresh();
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        purchaseInProgress = false;
        status = purchase.error?.message ?? 'Google Play 결제가 실패했어요.';
        _refresh();
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        purchaseInProgress = false;
        status = '구독 결제를 취소했어요.';
        _refresh();
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) continue;
      try {
        final token = purchase.verificationData.serverVerificationData;
        final result = await _functions
            .httpsCallable('verifyKyeobomGooglePlaySubscription')
            .call<Map<String, dynamic>>({
              'purchaseToken': token,
              'productId': purchase.productID,
            });
        if (result.data['premium'] != true) {
          throw StateError('Google Play 서버 검증이 완료되지 않았습니다.');
        }
        // Acknowledge/finish ONLY after backend verification. Unverified or
        // pending purchases must never be granted or acknowledged.
        if (purchase.pendingCompletePurchase) {
          await _store.completePurchase(purchase);
        }
        await refreshEntitlement();
        status = '구독이 확인됐어요. 프리미엄 기능을 사용할 수 있습니다.';
      } catch (error) {
        premium = false;
        status = '구매 검증 실패: $error. '
            '자동 결제 완료 처리를 하지 않았으니 잠시 뒤 구매 복원을 시도해 주세요.';
      } finally {
        purchaseInProgress = false;
        _refresh();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_purchaseListener?.cancel());
    super.dispose();
  }
}
