import 'package:flutter/material.dart';
import '../../core/components/app_bottom_sheet.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/services/selected_club_service.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';

/// Kullanıcının Takım / Kulüp Seçmesini Sağlayan Modal Sheet
class ClubSelectionSheet extends StatefulWidget {
  final List<String> availableClubs;
  final Map<String, int>? clubIdsByName;

  const ClubSelectionSheet({
    super.key,
    required this.availableClubs,
    this.clubIdsByName,
  });

  static Future<String?> show(
    BuildContext context, {
    required List<String> availableClubs,
    Map<String, int>? clubIdsByName,
  }) {
    return AppBottomSheet.show<String>(
      context,
      builder: (_) => ClubSelectionSheet(
        availableClubs: availableClubs,
        clubIdsByName: clubIdsByName,
      ),
    );
  }

  @override
  State<ClubSelectionSheet> createState() => _ClubSelectionSheetState();
}

class _ClubSelectionSheetState extends State<ClubSelectionSheet> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode()..addListener(_handleSearchFocusChange);
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchFocusChange() {
    if (mounted && _isSearchFocused != _searchFocusNode.hasFocus) {
      setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
    }
  }

  List<String> get _filteredClubs {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.availableClubs;
    return widget.availableClubs
        .where((c) => c.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final clubs = _filteredClubs;

    return AppBottomSheet(
      scrollable: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Başlık Alanı
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 20,
                color: palette.primary,
              ),
              AppSpacing.hSm,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Takımını Seç',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Yarışlardaki kulüp sporcularınızı otomatik vurgular',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                        color: palette.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (SelectedClubService.instance.hasSelectedClub) ...[
                AppSpacing.hSm,
                TextButton(
                  onPressed: () async {
                    await SelectedClubService.instance.clearClub();
                    if (context.mounted) Navigator.pop(context, '');
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: palette.statusDanger,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Kaldır', style: TextStyle(fontSize: 13)),
                ),
              ],
            ],
          ),
          AppSpacing.v12,

          // Arama Kutusu (Glass Level 3 stili, iç içe blur olmadan)
          SoftGlassPanel(
            level: 3,
            enableBlur: false,
            height: 48,
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            animationDuration: const Duration(milliseconds: 180),
            fillAlphaOverride: palette.isDark
                ? (_isSearchFocused ? 0.15 : 0.09)
                : (_isSearchFocused ? 0.20 : 0.14),
            borderAlphaOverride: palette.isDark
                ? (_isSearchFocused ? 0.34 : 0.16)
                : (_isSearchFocused ? 0.50 : 0.25),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_outlined,
                  size: 20,
                  color: palette.textSecondary,
                ),
                AppSpacing.h12,
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14.5,
                      color: palette.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Kulüp veya takım ara...',
                      hintStyle: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 14,
                        color: palette.textSecondary.withValues(alpha: 0.85),
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_outlined, size: 18),
                    color: palette.textSecondary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
              ],
            ),
          ),
          AppSpacing.v12,

          Divider(height: 1, thickness: 1, color: palette.divider),

          // Kulüpler Listesi
          Expanded(
            child: clubs.isEmpty
                ? Center(
                    child: Padding(
                      padding: AppSpacing.paddingAllLg,
                      child: Text(
                        'Aramanızla eşleşen kulüp bulunamadı.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13.5,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    itemCount: clubs.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: palette.divider,
                    ),
                    itemBuilder: (context, index) {
                      final club = clubs[index];
                      final isSelected =
                          SelectedClubService.instance.matches(club);

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            await SelectedClubService.instance.setClub(
                              id: widget.clubIdsByName?[club],
                              name: club,
                            );
                            if (context.mounted) Navigator.pop(context, club);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s12,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? palette.accent.withValues(alpha: 0.14)
                                        : palette.textPrimary
                                            .withValues(alpha: 0.05),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.shield_outlined,
                                    size: 16,
                                    color: isSelected
                                        ? palette.accent
                                        : palette.textSecondary,
                                  ),
                                ),
                                AppSpacing.h12,
                                Expanded(
                                  child: Text(
                                    StringUtils.toTitleCase(club),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 14.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? palette.accent
                                          : palette.textPrimary,
                                    ),
                                  ),
                                ),
                                if (isSelected) ...[
                                  AppSpacing.hSm,
                                  Icon(
                                    Icons.check_outlined,
                                    size: 20,
                                    color: palette.accent,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
