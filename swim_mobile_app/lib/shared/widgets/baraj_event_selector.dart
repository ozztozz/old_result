import 'package:flutter/material.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../data/models/baraj_rule.dart';

/// Barajlar sayfası ve Sporcu Detay sayfasında ortak kullanılan
/// Yer / Tarih filtreli Baraj Etkinlik Seçici bileşeni.
class BarajEventSelector extends StatelessWidget {
  final List<BarajEventOption> events;
  final BarajEventOption? activeEvent;
  final List<String> cities;
  final List<String> months;
  final String selectedCity;
  final String selectedMonth;
  final ValueChanged<String> onCityChanged;
  final ValueChanged<String> onMonthChanged;
  final ValueChanged<BarajEventOption> onEventSelected;
  final List<Widget> extraFilterChips;
  final VoidCallback? onOpenPdf;
  final VoidCallback? onOpenSummary;

  const BarajEventSelector({
    super.key,
    required this.events,
    required this.activeEvent,
    required this.cities,
    required this.months,
    required this.selectedCity,
    required this.selectedMonth,
    required this.onCityChanged,
    required this.onMonthChanged,
    required this.onEventSelected,
    this.extraFilterChips = const [],
    this.onOpenPdf,
    this.onOpenSummary,
  });

  static String formatMonth(String ym) {
    if (!ym.contains('-')) return ym;
    final parts = ym.split('-');
    if (parts.length < 2) return ym;
    const monthNames = {
      '01': 'Ocak',
      '02': 'Şubat',
      '03': 'Mart',
      '04': 'Nisan',
      '05': 'Mayıs',
      '06': 'Haziran',
      '07': 'Temmuz',
      '08': 'Ağustos',
      '09': 'Eylül',
      '10': 'Ekim',
      '11': 'Kasım',
      '12': 'Aralık',
    };
    return '${monthNames[parts[1]] ?? parts[1]} ${parts[0]}';
  }

  static List<String> extractCities(List<BarajEventOption> events) {
    final set = <String>{};
    for (final e in events) {
      final c = e.city.trim();
      if (c.isNotEmpty) set.add(c);
    }
    final list = set.toList()..sort();
    return list;
  }

  static List<String> extractMonths(List<BarajEventOption> events) {
    final set = <String>{};
    for (final e in events) {
      if (e.startDate.length >= 7) {
        set.add(e.startDate.substring(0, 7));
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  static List<BarajEventOption> filterEvents(
    List<BarajEventOption> events, {
    String city = '',
    String month = '',
  }) {
    return events.where((e) {
      if (city.isNotEmpty &&
          !e.city.toLowerCase().contains(city.toLowerCase())) {
        return false;
      }
      if (month.isNotEmpty && !e.startDate.startsWith(month)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasFilterRow =
        cities.isNotEmpty || months.isNotEmpty || extraFilterChips.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasFilterRow) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (cities.isNotEmpty)
                  _buildPopupChip(
                    context,
                    palette,
                    icon: Icons.location_on_outlined,
                    label: selectedCity.isEmpty ? 'Yer Seç' : selectedCity,
                    isActive: selectedCity.isNotEmpty,
                    allLabel: 'Tüm Yerler',
                    items: cities
                        .map((c) => PopupMenuItem<String>(value: c, child: Text(c)))
                        .toList(),
                    onSelected: onCityChanged,
                  ),
                if (cities.isNotEmpty && months.isNotEmpty) AppSpacing.hSm,
                if (months.isNotEmpty)
                  _buildPopupChip(
                    context,
                    palette,
                    icon: Icons.calendar_today_outlined,
                    label: selectedMonth.isEmpty
                        ? 'Tarih Seç'
                        : formatMonth(selectedMonth),
                    isActive: selectedMonth.isNotEmpty,
                    allLabel: 'Tüm Tarihler',
                    items: months
                        .map(
                          (m) => PopupMenuItem<String>(
                            value: m,
                            child: Text(formatMonth(m)),
                          ),
                        )
                        .toList(),
                    onSelected: onMonthChanged,
                  ),
                if ((cities.isNotEmpty || months.isNotEmpty) &&
                    extraFilterChips.isNotEmpty)
                  AppSpacing.hSm,
                ...extraFilterChips,
              ],
            ),
          ),
          AppSpacing.vSm,
        ],
        if (events.isNotEmpty && activeEvent != null)
          SoftGlassPanel(
            level: 3,
            borderRadius: AppRadius.buttonRadius,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.s12,
            ),
            onTap: () => showEventPickerSheet(
              context,
              events: events,
              activeEvent: activeEvent,
              onEventSelected: onEventSelected,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeEvent!.title,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: palette.textPrimary,
                        ),
                      ),
                      if (activeEvent!.city.isNotEmpty ||
                          activeEvent!.dateText.isNotEmpty) ...[
                        AppSpacing.vXs,
                        Text(
                          [
                            if (activeEvent!.dateText.isNotEmpty)
                              activeEvent!.dateText,
                            if (activeEvent!.city.isNotEmpty) activeEvent!.city,
                          ].join(' • '),
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                      if (activeEvent!.validityText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Geçerlilik: ${activeEvent!.validityText}',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: palette.accent,
                          ),
                        ),
                      ],
                      if (onOpenPdf != null || onOpenSummary != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onOpenPdf != null)
                              _buildActionBadge(
                                icon: Icons.picture_as_pdf_outlined,
                                label: 'Reglaman',
                                foreground: palette.accent,
                                background: palette.accentSoft,
                                onTap: onOpenPdf!,
                              ),
                            if (onOpenPdf != null && onOpenSummary != null)
                              const SizedBox(width: 8),
                            if (onOpenSummary != null)
                              _buildActionBadge(
                                icon: Icons.info_outline_rounded,
                                label: 'Özet',
                                foreground: palette.statusSuccess,
                                background: palette.statusSuccessBg,
                                onTap: onOpenSummary!,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                AppSpacing.hSm,
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: palette.textSecondary,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildActionBadge({
    required IconData icon,
    required String label,
    required Color foreground,
    required Color background,
    required VoidCallback onTap,
  }) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: foreground.withAlpha(90)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopupChip(
    BuildContext context,
    AppColorPalette palette, {
    required IconData icon,
    required String label,
    required bool isActive,
    required String allLabel,
    required List<PopupMenuEntry<String>> items,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (_) => [
        PopupMenuItem<String>(value: '', child: Text(allLabel)),
        ...items,
      ],
      child: SoftGlassPanel(
        level: 3,
        borderRadius: AppRadius.chipRadius,
        fillColorOverride: isActive ? palette.accentSoft : null,
        borderColor: isActive ? palette.accent : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? palette.accent : palette.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? palette.accent : palette.textPrimary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 16,
              color: isActive ? palette.accent : palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  static void showEventPickerSheet(
    BuildContext context, {
    required List<BarajEventOption> events,
    required BarajEventOption? activeEvent,
    required ValueChanged<BarajEventOption> onEventSelected,
  }) {
    final palette = context.palette;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.sheetRadius,
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s20,
                    AppSpacing.md,
                    AppSpacing.s12,
                    AppSpacing.s12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Etkinlik Seçin (${events.length})',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: palette.textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: palette.divider),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.s12,
                      AppSpacing.md,
                      AppSpacing.s20,
                    ),
                    itemCount: events.length,
                    separatorBuilder: (_, __) => AppSpacing.vSm,
                    itemBuilder: (_, i) {
                      final ev = events[i];
                      final isSelected = activeEvent != null &&
                          (ev.eventId != null && activeEvent.eventId != null
                              ? ev.eventId == activeEvent.eventId
                              : ev.title == activeEvent.title &&
                                  ev.dateText == activeEvent.dateText);
                      return SoftGlassPanel(
                        level: 2,
                        borderRadius: AppRadius.buttonRadius,
                        padding: const EdgeInsets.all(AppSpacing.s12),
                        fillColorOverride: isSelected
                            ? palette.accentSoft
                            : palette.surfaceSecondary,
                        borderColor:
                            isSelected ? palette.accent : palette.border,
                        onTap: () {
                          Navigator.pop(ctx);
                          onEventSelected(ev);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ev.title,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                                color: isSelected
                                    ? palette.accent
                                    : palette.textPrimary,
                              ),
                            ),
                            if (ev.dateText.isNotEmpty ||
                                ev.city.isNotEmpty ||
                                ev.validityText.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              if (ev.dateText.isNotEmpty || ev.city.isNotEmpty)
                                Text(
                                  [
                                    if (ev.dateText.isNotEmpty) ev.dateText,
                                    if (ev.city.isNotEmpty) ev.city,
                                  ].join(' • '),
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 12,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              if (ev.validityText.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Baraj Geçerlilik: ${ev.validityText}',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: palette.primary,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
