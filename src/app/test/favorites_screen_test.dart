import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:harmony_user_app/screens/category_favorites_screen.dart';
import 'package:harmony_user_app/screens/interesting_topics_screen.dart';
import 'package:harmony_user_app/services/favorites_service.dart';
import 'package:harmony_user_app/widgets/favorite_item_card.dart';

class _Favorites extends ChangeNotifier implements FavoritesService {
  _Favorites(this.items);

  final List<Map<String, dynamic>> items;
  String? removedUrl;
  bool failRemoval = false;

  @override
  List<Map<String, dynamic>> get favorites => List.unmodifiable(items);

  @override
  Future<void> removeFavorite(String url) async {
    removedUrl = url;
    if (failRemoval) throw StateError('Test failure');
    items.removeWhere((item) => FavoritesService.contentUrl(item) == url);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Routes extends NavigatorObserver {
  Route<dynamic>? pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed = route;
  }
}

void main() {
  const url = 'https://www.youtube.com/watch?v=abc12345678';
  final legacyItem = <String, dynamic>{
    'title': 'Saved topic',
    'youtubeUrl': '',
    'url': url,
  };

  test('legacy favourites fall back to a nonempty URL', () {
    expect(FavoritesService.contentUrl(legacyItem), url);
    expect(FavoritesService.contentUrl({'youtubeUrl': '  ', 'url': url}), url);
    expect(FavoritesService.contentUrl({}), isEmpty);
  });

  testWidgets('remove X updates the open category without playing content', (tester) async {
    final service = _Favorites([Map.of(legacyItem)]);
    final routes = _Routes();
    await tester.pumpWidget(ChangeNotifierProvider<FavoritesService>.value(
      value: service,
      child: MaterialApp(
        navigatorObservers: [routes],
        home: CategoryFavoritesScreen(
          categoryName: 'Topics',
          favorites: [legacyItem],
        ),
      ),
    ));
    final initialRoute = routes.pushed;
    expect(find.text('Saved topic'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(service.removedUrl, url);
    expect(find.text('Saved topic'), findsNothing);
    expect(find.text('No items found'), findsOneWidget);
    expect(routes.pushed, same(initialRoute));
  });

  testWidgets('failed removal retains the item and shows feedback', (tester) async {
    final service = _Favorites([Map.of(legacyItem)])..failRemoval = true;
    await tester.pumpWidget(ChangeNotifierProvider<FavoritesService>.value(
      value: service,
      child: MaterialApp(home: CategoryFavoritesScreen(
        categoryName: 'Topics', favorites: [legacyItem],
      )),
    ));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('Saved topic'), findsOneWidget);
    expect(find.text('Could not remove favourite. Please try again.'), findsOneWidget);
  });

  testWidgets('old YouTube favourite opens the same viewer as Topics', (tester) async {
    final routes = _Routes();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [routes],
      home: Scaffold(body: SizedBox(
        width: 160, height: 240,
        child: FavoriteItemCard(topic: legacyItem),
      )),
    ));
    await tester.tap(find.byIcon(Icons.play_arrow));
    final route = routes.pushed! as MaterialPageRoute<dynamic>;
    final screen = route.builder(tester.element(find.byType(FavoriteItemCard)));
    expect(screen, isA<TopicsFullscreenYoutubeScreen>());
    expect((screen as TopicsFullscreenYoutubeScreen).url, url);
    expect(screen.title, 'Saved topic');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}