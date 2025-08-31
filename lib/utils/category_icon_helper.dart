import 'package:flutter/material.dart';

class CategoryIconHelper {
  static const Map<String, String> _iconPaths = {
    'food': 'assets/icons/category/food.svg',
    'transport': 'assets/icons/category/transport.svg',
    'entertainment': 'assets/icons/category/entertainment.svg',
    'shopping': 'assets/icons/category/shopping.svg',
    'health': 'assets/icons/category/health.svg',
    'education': 'assets/icons/category/education.svg',
    'utilities': 'assets/icons/category/utilities.svg',
    'housing': 'assets/icons/category/housing.svg',
    'insurance': 'assets/icons/category/insurance.svg',
    'other': 'assets/icons/category/other.svg',
    'cafe': 'assets/icons/category/cafe.svg',
    'restaurant': 'assets/icons/category/restaurant.svg',
    'movie': 'assets/icons/category/movie.svg',
    'game': 'assets/icons/category/game.svg',
    'sport': 'assets/icons/category/sport.svg',
    'travel': 'assets/icons/category/travel.svg',
    'clothing': 'assets/icons/category/clothing.svg',
    'cosmetics': 'assets/icons/category/cosmetics.svg',
    'electronics': 'assets/icons/category/electronics.svg',
    'medicine': 'assets/icons/category/medicine.svg',
    'book': 'assets/icons/category/book.svg',
    'internet': 'assets/icons/category/internet.svg',
    'car': 'assets/icons/category/car.svg',
    'gift': 'assets/icons/category/gift.svg',
    'money': 'assets/icons/category/money.svg',
    'heart': 'assets/icons/category/heart.svg',
    'star': 'assets/icons/category/star.svg',
  };

  /// アイコンIDからアイコンパスを取得
  static String? getIconPath(String iconId) {
    return _iconPaths[iconId];
  }

  /// アイコンIDが有効かチェック
  static bool isValidIconId(String iconId) {
    return _iconPaths.containsKey(iconId);
  }

  /// 利用可能なアイコンID一覧を取得
  static List<String> getAvailableIconIds() {
    return _iconPaths.keys.toList();
  }

  /// アイコンIDからアイコンウィジェットを取得（SVG使用時）
  static Widget? getIconWidget(String iconId, {
    double? width,
    double? height,
    Color? color,
  }) {
    final path = getIconPath(iconId);
    if (path == null) return null;

    // SVGを使用する場合の例（flutter_svgパッケージが必要）
    // return SvgPicture.asset(
    //   path,
    //   width: width,
    //   height: height,
    //   colorFilter: color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null,
    // );

    // または、アイコンフォントを使用する場合
    return Icon(
      _getIconData(iconId),
      size: width ?? height ?? 24,
      color: color,
    );
  }

  /// アイコンIDからIconDataを取得（アイコンフォント使用時）
  static IconData _getIconData(String iconId) {
    switch (iconId) {
      case 'food':
        return Icons.restaurant;
      case 'transport':
        return Icons.directions_car;
      case 'entertainment':
        return Icons.movie;
      case 'shopping':
        return Icons.shopping_cart;
      case 'health':
        return Icons.local_hospital;
      case 'education':
        return Icons.school;
      case 'utilities':
        return Icons.electric_bolt;
      case 'housing':
        return Icons.home;
      case 'insurance':
        return Icons.security;
      case 'cafe':
        return Icons.coffee;
      case 'restaurant':
        return Icons.restaurant_menu;
      case 'movie':
        return Icons.movie;
      case 'game':
        return Icons.games;
      case 'sport':
        return Icons.sports_soccer;
      case 'travel':
        return Icons.flight;
      case 'clothing':
        return Icons.checkroom;
      case 'cosmetics':
        return Icons.face;
      case 'electronics':
        return Icons.devices;
      case 'medicine':
        return Icons.medication;
      case 'book':
        return Icons.book;
      case 'internet':
        return Icons.wifi;
      case 'car':
        return Icons.directions_car;
      case 'gift':
        return Icons.card_giftcard;
      case 'money':
        return Icons.attach_money;
      case 'heart':
        return Icons.favorite;
      case 'star':
        return Icons.star;
      case 'other':
      default:
        return Icons.category;
    }
  }
}
