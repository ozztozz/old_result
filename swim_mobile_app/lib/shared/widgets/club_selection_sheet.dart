import 'package:flutter/material.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/services/selected_club_service.dart';

String _toTitleCase(String text) {
  if (text.isEmpty) return text;
  return text.split(' ').map((word) {
    if (word.isEmpty) return word;
    final lower = word.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }).join(' ');
}

/// Kullanıcının Takım / Kulüp Seçmesini Sağlayan Apple Esintili Modal Sheet
class ClubSelectionSheet extends StatefulWidget {
  final List<String> availableClubs;

  const ClubSelectionSheet({
    super.key,
    required this.availableClubs,
  });

  static Future<String?> show(BuildContext context, {required List<String> availableClubs}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ClubSelectionSheet(availableClubs: availableClubs),
    );
  }

  @override
  State<ClubSelectionSheet> createState() => _ClubSelectionSheetState();
}

class _ClubSelectionSheetState extends State<ClubSelectionSheet> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filteredClubs {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.availableClubs;
    return widget.availableClubs.where((c) => c.toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final clubs = _filteredClubs;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.sheetRadius,
        boxShadow: [
          BoxShadow(
            color: palette.textPrimary.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Üst Tutamaç (Handle)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: AppRadius.chipRadius,
                ),
              ),
            ),

            // Başlık Alanı
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 22,
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
                        ),
                        Text(
                          'Yarışlardaki kulüp sporcularınızı otomatik vurgular',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (SelectedClubService.instance.hasSelectedClub)
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
              ),
            ),

            // Arama Kutusu
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: palette.surfaceSecondary,
                  borderRadius: AppRadius.inputRadius,
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    color: palette.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Kulüp veya takım ara...',
                    hintStyle: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      color: palette.textMuted,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: palette.textSecondary,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            color: palette.textSecondary,
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  ),
                ),
              ),
            ),

            Divider(height: 1, thickness: 1, color: palette.divider),

            // Kulüpler Listesi
            Expanded(
              child: clubs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Aramanızla eşleşen kulüp bulunamadı.',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13.5,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: clubs.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 1,
                        color: palette.divider,
                        indent: 52,
                      ),
                      itemBuilder: (context, index) {
                        final club = clubs[index];
                        final isSelected = SelectedClubService.instance.matches(club);

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () async {
                              await SelectedClubService.instance.setClub(name: club);
                              if (context.mounted) Navigator.pop(context, club);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 13,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? palette.primary
                                          : palette.surfaceSecondary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.shield_rounded,
                                      size: 16,
                                      color: isSelected ? Colors.white : palette.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      _toTitleCase(club),
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 14.5,
                                        fontWeight:
                                            isSelected ? FontWeight.w600 : FontWeight.w400,
                                        color: isSelected
                                            ? palette.primary
                                            : palette.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_rounded,
                                      size: 20,
                                      color: palette.primary,
                                    ),
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
      ),
    );
  }
}
