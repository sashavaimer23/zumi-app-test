import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/results.dart';
import '../widgets/zicons.dart';

/// Результаты поиска (макет search_houses): строка поиска, счётчик, Sort/Filter, список.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.initial, this.title});
  final SearchFilters initial;
  final String? title;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late SearchFilters _filters = widget.initial;
  late final _ctrl = TextEditingController(text: widget.initial.query);
  Future<int>? _countFuture;
  int _loadedVersion = -1;
  int _token = 0;

  void _reload() {
    _token++;
    _countFuture = context.read<AppState>().repo.countListings(_filters);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => setState(() {
        _filters = _filters.copy()..query = _ctrl.text;
        _reload();
      });

  @override
  Widget build(BuildContext context) {
    final version = context.select<AppState, int>((s) => s.dataVersion);
    if (version != _loadedVersion) {
      _loadedVersion = version;
      _reload();
    }

    return Scaffold(
      floatingActionButton: MapFab(filters: _filters),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(slivers: [
          // строка поиска с кнопкой «назад» появляется снова, как только листаешь чуть вверх
          SliverAppBar(
            floating: true,
            snap: true,
            primary: false,
            automaticallyImplyLeading: false,
            toolbarHeight: 82,
            titleSpacing: 0,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Zc.bg,
            surfaceTintColor: Colors.transparent,
            title: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
              child: Row(children: [
                IconButton(
                  icon: const Icon(ZI.back, color: Zc.green),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Container(
                    height: 58,
                    padding: const EdgeInsets.only(left: 16, right: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(29),
                      boxShadow: const [BoxShadow(color: Zc.shadow, blurRadius: 14, offset: Offset(0, 4))],
                    ),
                    child: Row(children: [
                      const Icon(ZI.search, color: Zc.orange, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            hintText: 'Search neighbourhoods…',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _submit,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(color: Zc.orange, shape: BoxShape.circle),
                          child: const Icon(ZI.caretRight, color: Colors.white, size: 30),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          if (widget.title != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 20, 26, 0),
                child: Text(widget.title!, style: zHeadline(context, size: 32)),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: CategoryChips(
                selected: _filters.propertyType,
                onChanged: (t) => setState(() {
                  _filters = _filters.copy()..propertyType = t;
                  _reload();
                }),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<int>(
              future: _countFuture,
              builder: (context, snap) => ResultsHeader(
                label: snap.data == null ? 'Loading…' : countLabel(snap.data!, _filters.propertyType),
                filters: _filters,
                onChanged: (f) => setState(() {
                  _filters = f;
                  _reload();
                }),
              ),
            ),
          ),
          ResultsSliver(key: ValueKey('search$_token'), filters: _filters),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ]),
      ),
    );
  }
}
