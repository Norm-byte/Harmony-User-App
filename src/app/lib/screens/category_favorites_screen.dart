import 'package:flutter/material.dart';
import '../widgets/favorite_item_card.dart';
import '../widgets/gradient_scaffold.dart';

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
      body: favorites.isEmpty
          ? const Center(child: Text("No items found", style: TextStyle(color: Colors.white)))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.65,
              ),
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                final item = favorites[index];
                return FavoriteItemCard(topic: item);
              },
            ),
    );
  }
}
