import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/results.dart';
import '../widgets/wide_card.dart';
import 'shell.dart';
import '../widgets/zicons.dart';

/// Сохранённые объявления (макет Saved)
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  PropertyType? _type;
  String _key = '';
  Future<List<Property>>? _future;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ids = app.favorites.toList();
    final key = '${ids.join(',')}#${app.dataVersion}';
    if (key != _key) {
      _key = key;
      _future = app.repo.byIds(ids);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 18, 26, 14),
            child: Row(children: [
              Expanded(child: Text('Saved', style: zHeadline(context, size: 40))),
            ]),
          ),
          CategoryChips(
            selected: _type,
            onChanged: (t) => setState(() => _type = t),
            padding: const EdgeInsets.symmetric(horizontal: 24),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: FutureBuilder<List<Property>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator(color: Zc.orange));
                }
                final all = snap.data ?? const <Property>[];
                final list = _type == null ? all : all.where((p) => p.propertyType == _type).toList();
                if (list.isEmpty) {
                  return EmptyState(
                    icon: ZI.heart,
                    title: all.isEmpty ? 'No saved homes yet' : 'Nothing in this category',
                    subtitle: 'Tap the heart on any listing to save it here.',
                    action: all.isEmpty
                        ? OutlinedButton(
                            onPressed: () => Shell.of(context)?.go(0),
                            child: const Text('Explore homes'),
                          )
                        : null,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, Shell.navSpace + 10),
                  itemCount: list.length,
                  itemBuilder: (_, i) => isDesktop(context)
                      ? Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
                            child: PropertyWideCard(p: list[i], onTap: () => openProperty(context, list[i])),
                          ),
                        )
                      : PropertyCard(p: list[i], onTap: () => openProperty(context, list[i])),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
