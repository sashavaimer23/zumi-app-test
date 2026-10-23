import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/zicons.dart';

/// Открывает экран фильтров. Возвращает новые фильтры или null, если закрыли.
Future<SearchFilters?> showFiltersSheet(BuildContext context, SearchFilters current) {
  return showModalBottomSheet<SearchFilters>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Zc.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => FractionallySizedBox(heightFactor: 0.96, child: FiltersSheet(initial: current)),
  );
}

Future<SortBy?> showSortSheet(BuildContext context, SortBy current) {
  return showModalBottomSheet<SortBy>(
    context: context,
    backgroundColor: Zc.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Sort by', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Zc.green)),
          const SizedBox(height: 8),
          for (final s in SortBy.values)
            ListTile(
              title: Text(s.label),
              trailing: RadioDot(selected: s == current),
              onTap: () => Navigator.pop(ctx, s),
            ),
        ]),
      ),
    ),
  );
}

class FiltersSheet extends StatefulWidget {
  const FiltersSheet({super.key, required this.initial});
  final SearchFilters initial;

  @override
  State<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<FiltersSheet> {
  late SearchFilters f = widget.initial.copy();
  List<double> _prices = []; // цены подходящих объявлений (в выбранной валюте) — для гистограммы
  int? _total; // сколько объявлений найдётся с текущими фильтрами
  bool _loading = true;
  Timer? _debounce;
  final _minSqm = TextEditingController();
  final _maxSqm = TextEditingController();

  @override
  void initState() {
    super.initState();
    _minSqm.text = f.minSqm?.round().toString() ?? '';
    _maxSqm.text = f.maxSqm?.round().toString() ?? '';
    _refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _minSqm.dispose();
    _maxSqm.dispose();
    super.dispose();
  }

  void _changed(VoidCallback fn) {
    setState(fn);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _refresh);
  }

  Future<void> _refresh() async {
    final repo = context.read<AppState>().repo;
    final snapshot = f.copy();
    try {
      final res = await Future.wait<dynamic>([repo.priceSamples(snapshot), repo.countListings(snapshot)]);
      if (!mounted) return;
      setState(() {
        _prices = res[0] as List<double>;
        _total = res[1] as int;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Шкала цен зависит от типа сделки и валюты
  double get _maxBound {
    final usd = f.currency == 'USD';
    if (f.dealType == DealType.sale) return usd ? 1000000 : 5000000;
    if (f.rentPeriod == 'day') return usd ? 500 : 5000;
    if (f.dealType == DealType.rent) return usd ? 10000 : 100000;
    return usd ? 1000000 : 5000000;
  }

  double get _step => _maxBound / 50;

  @override
  Widget build(BuildContext context) {
    final isRent = f.dealType != DealType.sale;
    return Column(
      children: [
        // --- шапка
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
          child: Row(children: [
            const Expanded(
              child: Text('Filters', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: Zc.text)),
            ),
            TextButton(
              onPressed: () => _changed(() {
                final keep = f;
                f = SearchFilters(
                    city: keep.city, query: keep.query, propertyType: keep.propertyType, sort: keep.sort,
                    currency: keep.currency);
                _minSqm.clear();
                _maxSqm.clear();
              }),
              child: const Text('Reset', style: TextStyle(color: Zc.grey)),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(ZI.close, color: Zc.orange, size: 32),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              _wrap([
                ZChip(
                  label: 'To buy',
                  selected: f.dealType == DealType.sale,
                  onTap: () => _changed(() {
                    f.dealType = f.dealType == DealType.sale ? null : DealType.sale;
                    f.rentPeriod = null;
                    f.leaseTerm = null;
                    f.minPrice = f.maxPrice = null;
                  }),
                ),
                ZChip(
                  label: 'To rent',
                  selected: f.dealType == DealType.rent,
                  onTap: () => _changed(() {
                    f.dealType = f.dealType == DealType.rent ? null : DealType.rent;
                    f.minPrice = f.maxPrice = null;
                  }),
                ),
              ]),
              if (f.dealType == DealType.rent) ...[
                _title('Rental type'),
                _wrap([
                  ZChip(
                    label: 'Long-term',
                    selected: f.rentPeriod == 'month',
                    onTap: () => _changed(() {
                      f.rentPeriod = f.rentPeriod == 'month' ? null : 'month';
                      f.minPrice = f.maxPrice = null;
                    }),
                  ),
                  ZChip(
                    label: 'Daily',
                    selected: f.rentPeriod == 'day',
                    onTap: () => _changed(() {
                      f.rentPeriod = f.rentPeriod == 'day' ? null : 'day';
                      f.minPrice = f.maxPrice = null;
                    }),
                  ),
                ]),
              ],
              _title('Property type'),
              _wrap([
                for (final t in PropertyType.values)
                  ZChip(
                    label: t.label,
                    selected: f.propertyType == t,
                    onTap: () => _changed(() => f.propertyType = f.propertyType == t ? null : t),
                  ),
              ]),
              _title('Location'),
              _AreaField(
                city: f.city,
                areaId: f.areaId,
                onChanged: (id) => _changed(() => f.areaId = id),
              ),
              Row(children: [
                Expanded(child: _title('Price range')),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: Zc.orangeSoft,
                      selectedForegroundColor: Zc.orange,
                      foregroundColor: Zc.grey,
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(value: 'ZMW', label: Text('ZMW')),
                      ButtonSegment(value: 'USD', label: Text('USD')),
                    ],
                    selected: {f.currency},
                    onSelectionChanged: (v) => _changed(() {
                      f.currency = v.first;
                      f.minPrice = f.maxPrice = null;
                    }),
                  ),
                ),
              ]),
              _PriceRange(
                prices: _prices,
                maxBound: _maxBound,
                step: _step,
                min: f.minPrice,
                max: f.maxPrice,
                currency: f.currency,
                onChanged: (lo, hi) => _changed(() {
                  f.minPrice = lo <= 0 ? null : lo;
                  f.maxPrice = hi >= _maxBound ? null : hi;
                }),
              ),
              if (f.hasPrice)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Only listings priced in ${f.currency} are shown.',
                      style: const TextStyle(fontSize: 12, color: Zc.grey)),
                ),
              _title('Bedrooms'),
              _plusRow(f.minBedrooms, (v) => _changed(() => f.minBedrooms = v)),
              _title('Bathrooms'),
              _plusRow(f.minBathrooms, (v) => _changed(() => f.minBathrooms = v)),
              _title('Renovation'),
              _wrap([
                for (final e in renovationLabels.entries)
                  ZChip(
                    label: e.value,
                    selected: f.renovation.contains(e.key),
                    onTap: () => _changed(() =>
                        f.renovation.contains(e.key) ? f.renovation.remove(e.key) : f.renovation.add(e.key)),
                  ),
              ]),
              if (isRent) ...[
                _title('Tenant preferences'),
                _switch('Kids allowed', f.kidsAllowed, (v) => _changed(() => f.kidsAllowed = v)),
                _switch('Pets allowed', f.petsAllowed, (v) => _changed(() => f.petsAllowed = v)),
              ],
              _title('In the property'),
              _wrap([
                for (final e in amenityLabels.entries)
                  ZChip(
                    label: e.value,
                    selected: f.amenities.contains(e.key),
                    onTap: () => _changed(() =>
                        f.amenities.contains(e.key) ? f.amenities.remove(e.key) : f.amenities.add(e.key)),
                  ),
              ]),
              _title('Verification'),
              _switch('Only Verified listings', f.onlyVerified, (v) => _changed(() => f.onlyVerified = v)),
              _switch('Location confirmed on site', f.onlyLocationVerified,
                  (v) => _changed(() => f.onlyLocationVerified = v)),
              _title('Listed by'),
              _switch('Owners only', f.onlyOwner, (v) => _changed(() {
                    f.onlyOwner = v;
                    if (v) f.onlyAgent = false;
                  })),
              _switch('Agents only', f.onlyAgent, (v) => _changed(() {
                    f.onlyAgent = v;
                    if (v) f.onlyOwner = false;
                  })),
              if (isRent) ...[
                _title('Lease term'),
                _wrap([
                  ZChip(
                    label: 'From a year',
                    selected: f.leaseTerm == 'year',
                    onTap: () => _changed(() => f.leaseTerm = f.leaseTerm == 'year' ? null : 'year'),
                  ),
                  ZChip(
                    label: 'A few months',
                    selected: f.leaseTerm == 'months',
                    onTap: () => _changed(() => f.leaseTerm = f.leaseTerm == 'months' ? null : 'months'),
                  ),
                ]),
              ],
              _title('Area m²'),
              Row(children: [
                Expanded(child: _sqmField(_minSqm, 'From', (v) => _changed(() => f.minSqm = v))),
                const SizedBox(width: 16),
                Expanded(child: _sqmField(_maxSqm, 'To', (v) => _changed(() => f.maxSqm = v))),
              ]),
              const SizedBox(height: 12),
            ],
          ),
        ),
        // --- кнопка «Show N listings»
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: PrimaryButton(
              width: double.infinity,
              label: _loading || _total == null ? 'Loading…' : 'Show $_total ${_total == 1 ? 'listing' : 'listings'}',
              onPressed: () => Navigator.pop(context, f),
            ),
          ),
        ),
      ],
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 14),
        child: Text(t, style: const TextStyle(fontSize: 18, color: Zc.text)),
      );

  Widget _wrap(List<Widget> children) => Wrap(spacing: 12, runSpacing: 12, children: children);

  Widget _plusRow(int? value, ValueChanged<int?> onChanged) => _wrap([
        for (var n = 1; n <= 4; n++)
          ZChip(label: '$n+', selected: value == n, onTap: () => onChanged(value == n ? null : n)),
      ]);

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15, color: Zc.grey))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: Zc.orange,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: Zc.lightGrey,
          ),
        ]),
      );

  Widget _sqmField(TextEditingController c, String hint, ValueChanged<double?> onChanged) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: hint,
          suffixText: 'm²',
          fillColor: Zc.bg,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: Zc.lightGrey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: Zc.orange),
          ),
        ),
        onChanged: (s) => onChanged(double.tryParse(s.replaceAll(',', '.'))),
      );
}

// ----------------------------------------------------------------------
// Выбор района
// ----------------------------------------------------------------------
class _AreaField extends StatelessWidget {
  const _AreaField({required this.city, required this.areaId, required this.onChanged});
  final String city;
  final int? areaId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Area>>(
      future: context.read<AppState>().areas(),
      builder: (context, snap) {
        final areas = snap.data ?? const <Area>[];
        Area? selected;
        for (final a in areas) {
          if (a.id == areaId) selected = a;
        }
        return InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () async {
            final picked = await pickArea(context, areas, allowAll: true);
            if (picked != null) onChanged(picked.id == -1 ? null : picked.id);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Zc.lightGrey),
            ),
            child: Row(children: [
              const Icon(ZI.pinFill, color: Zc.orange, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  selected == null ? '$city, all neighbourhoods' : '$city, ${selected.name}',
                  style: const TextStyle(color: Zc.grey, fontSize: 14),
                ),
              ),
              const Icon(ZI.caretDown, color: Zc.grey),
            ]),
          ),
        );
      },
    );
  }
}

/// Список районов (используется в фильтрах и при подаче объявления)
Future<Area?> pickArea(BuildContext context, List<Area> areas, {bool allowAll = false}) {
  return showModalBottomSheet<Area>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Zc.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => FractionallySizedBox(
      heightFactor: 0.7,
      child: Column(children: [
        const Padding(
          padding: EdgeInsets.all(18),
          child: Text('Select the area', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Zc.green)),
        ),
        Expanded(
          child: ListView(children: [
            if (allowAll)
              ListTile(
                leading: const Icon(ZI.globe, color: Zc.green),
                title: const Text('All neighbourhoods'),
                onTap: () => Navigator.pop(ctx, const Area(id: -1, city: '', name: '', lat: 0, lng: 0)),
              ),
            for (final a in areas)
              ListTile(
                leading: const Icon(ZI.pin, color: Zc.orange),
                title: Text(a.name),
                subtitle: Text(a.city),
                onTap: () => Navigator.pop(ctx, a),
              ),
          ]),
        ),
      ]),
    ),
  );
}

// ----------------------------------------------------------------------
// Ценовой диапазон с гистограммой, как в макете
// ----------------------------------------------------------------------
class _PriceRange extends StatelessWidget {
  const _PriceRange({
    required this.prices,
    required this.maxBound,
    required this.step,
    required this.min,
    required this.max,
    required this.onChanged,
    this.currency = 'ZMW',
  });

  final String currency;
  final List<double> prices;
  final double maxBound;
  final double step;
  final double? min;
  final double? max;
  final void Function(double lo, double hi) onChanged;

  static const _bins = 26;

  @override
  Widget build(BuildContext context) {
    final lo = (min ?? 0).clamp(0, maxBound).toDouble();
    final hi = (max ?? maxBound).clamp(0, maxBound).toDouble();
    final counts = List<int>.filled(_bins, 0);
    for (final p in prices) {
      final i = ((p / maxBound) * _bins).floor().clamp(0, _bins - 1).toInt();
      counts[i]++;
    }
    final peak = math.max(1, counts.reduce(math.max));

    return Column(children: [
      SizedBox(
        height: 70,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < _bins; i++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    height: 4 + 66 * counts[i] / peak,
                    color: (i + 0.5) / _bins * maxBound >= lo && (i + 0.5) / _bins * maxBound <= hi
                        ? Zc.orange
                        : Zc.orangeTint,
                  ),
                ),
            ],
          ),
        ),
      ),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: Zc.orange,
          inactiveTrackColor: Zc.lightGrey,
          thumbColor: Colors.white,
          overlayColor: Zc.orangeTint,
          trackHeight: 3,
          rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 16, elevation: 3),
        ),
        child: RangeSlider(
          values: RangeValues(lo, hi),
          min: 0,
          max: maxBound,
          divisions: (maxBound / step).round(),
          onChanged: (v) => onChanged(v.start, v.end),
        ),
      ),
      Row(children: [
        Expanded(child: _pill('Min', formatMoney(lo, currency))),
        const SizedBox(width: 24),
        Expanded(
            child: _pill('Max', hi >= maxBound ? '${formatMoney(maxBound, currency)} +' : formatMoney(hi, currency))),
      ]),
    ]);
  }

  Widget _pill(String label, String value) => Column(children: [
        Text(label, style: const TextStyle(color: Zc.grey)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Zc.lightGrey),
          ),
          alignment: Alignment.center,
          child: Text(value, style: const TextStyle(fontSize: 14)),
        ),
      ]);
}
