import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/results.dart';
import 'home_screen.dart';
import 'search_screen.dart';

/// Все районы города с количеством объявлений
class NeighborhoodsScreen extends StatelessWidget {
  const NeighborhoodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Neighbourhoods')),
      floatingActionButton: MapFab(filters: SearchFilters()),
      body: FutureBuilder<List<dynamic>>(
        future: Future.wait<dynamic>([app.areas(), app.repo.areaCounts()]),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Zc.orange));
          final areas = snap.data![0] as List<Area>;
          final counts = snap.data![1] as Map<int, int>;
          final sorted = [...areas]..sort((a, b) => (counts[b.id] ?? 0) - (counts[a.id] ?? 0));
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.9,
            ),
            itemCount: sorted.length,
            itemBuilder: (_, i) => NeighborhoodCard(
              area: sorted[i],
              count: counts[sorted[i].id] ?? 0,
              width: double.infinity,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SearchScreen(
                    initial: SearchFilters(city: sorted[i].city, areaId: sorted[i].id),
                    title: sorted[i].name,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
