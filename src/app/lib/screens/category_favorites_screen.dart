import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/favorites_service.dart';
import '../widgets/favorite_item_card.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/locked_feature_widget.dart';

class CategoryFavoritesScreen extends StatelessWidget {
  final String categoryName;
  final List<Map<String, dynamic>> favorites;

  const CategoryFavoritesScreen({
    super.key,
    required this.categoryName,
    required this.favorites,
  });

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: Text(categoryName),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: LockedFeatureWidget(
        featureName: "Favorites",
        child: Consumer<FavoritesService>(
          builder: (context, service, _) {
            final categoryItems = service.favorites.where((item) {
              final url = FavoritesService.contentUrl(item);
              return favorites.any((original) =>
                  FavoritesService.contentUrl(original) == url);
            }).toList();
            return categoryItems.isEmpty
            ? const Center(child: Text("No items found", style: TextStyle(color: Colors.white)))
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.65,
                ),
                itemCount: categoryItems.length,
                itemBuilder: (context, index) {
                  final item = categoryItems[index];
                  return FavoriteItemCard(topic: item);
                },
              );
          },
        ),
      ),
    );
  }
}
