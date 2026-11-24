import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../core/components/soft_glass_panel.dart';
import '../../core/theme/tokens/tokens.dart';
import '../../core/utils/string_utils.dart';
import '../../data/models/athlete.dart';
import '../../data/models/meet.dart';
import '../../data/repositories/swim_repository.dart';
import 'club_detail_screen.dart';

/// Harita Üzerinde Kulüp Arama Ekranı
class ClubMapSearchScreen extends StatefulWidget {
  final SwimRepository repository;
  final ValueChanged<MeetSummary>? onMeetSelected;
  final String initialKind;

  const ClubMapSearchScreen({
    super.key,
    required this.repository,
    this.onMeetSelected,
    this.initialKind = 'all',
  });

  @override
  State<ClubMapSearchScreen> createState() => _ClubMapSearchScreenState();
}

class _ClubMapSearchScreenState extends State<ClubMapSearchScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  bool _isLoading = true;
  bool _isLocating = false;
  List<ClubSearchItem> _clubs = [];
  ClubSearchItem? _selectedClub;
  LatLng? _userLocation;
  double _currentZoom = 5.7;
  late String _kind;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _loadMapClubs();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMapClubs() async {
    setState(() => _isLoading = true);
    try {
      final list = await widget.repository.getMapClubs(
        q: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        kind: _kind,
      );
      if (!mounted) return;
      setState(() {
        _clubs = list;
        _isLoading = false;
        if (_selectedClub != null &&
            !list.any((c) => c.id == _selectedClub!.id)) {
          _selectedClub = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _centerOnUser() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Konum servisi kapalı.')),
          );
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Konum izni gerekli.')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      final point = LatLng(pos.latitude, pos.longitude);
      setState(() => _userLocation = point);
      _mapController.move(point, 11.5);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konum alınamadı.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(39.0, 35.0),
              initialZoom: 5.7,
              onTap: (_, __) => setState(() => _selectedClub = null),
              onPositionChanged: (camera, _) {
                final z = camera.zoom;
                if ((z >= 11) != (_currentZoom >= 11)) {
                  setState(() => _currentZoom = z);
                } else {
                  _currentZoom = z;
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.kulvar.swim_mobile_app',
              ),
              MarkerLayer(
                markers: [
                  if (_userLocation != null)
                    Marker(
                      point: _userLocation!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ..._clubs
                      .where((c) => c.latitude != null && c.longitude != null)
                      .map((club) {
                    final isSelected = _selectedClub?.id == club.id;
                    final showLabel = isSelected || _currentZoom >= 11;
                    final pinColor = isSelected
                        ? palette.accent
                        : (club.isSchool
                            ? palette.infoCyan
                            : const Color(0xFF2563EB));
                    final size = isSelected ? 40.0 : 32.0;
                    final shortName = StringUtils.toTitleCase(club.name)
                        .replaceAll(
                          RegExp(
                            r'\b(Gençlik Ve Spor Kulübü|Spor Kulübü Derneği|Spor Kulübü|Kulübü)\b',
                            caseSensitive: false,
                          ),
                          '',
                        )
                        .trim();
                    final labelText = shortName.isNotEmpty
                        ? shortName
                        : StringUtils.toTitleCase(club.name);
                    return Marker(
                      point: LatLng(club.latitude!, club.longitude!),
                      width: showLabel ? 190 : size,
                      height: size,
                      alignment: showLabel ? Alignment.centerLeft : Alignment.center,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedClub = club);
                          _mapController.move(
                            LatLng(club.latitude!, club.longitude!),
                            _mapController.camera.zoom < 11
                                ? 12
                                : _mapController.camera.zoom,
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                color: pinColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isSelected ? 0.30 : 0.20,
                                    ),
                                    blurRadius: isSelected ? 10 : 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Icon(
                                club.isSchool
                                    ? Icons.school_rounded
                                    : Icons.shield_rounded,
                                size: isSelected ? 20 : 15,
                                color: Colors.white,
                              ),
                            ),
                            if (showLabel) ...[
                              const SizedBox(width: 5),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.94),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.black.withValues(alpha: 0.12),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.12),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    labelText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),

          // Üst Arama & Filtre Barı
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      GlassCircleButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        tooltip: 'Geri',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SoftGlassPanel(
                          level: 2,
                          borderRadius: BorderRadius.circular(14),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: palette.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: (_) {
                                    _debounce?.cancel();
                                    _debounce = Timer(
                                      const Duration(milliseconds: 350),
                                      _loadMapClubs,
                                    );
                                  },
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 13.5,
                                    color: palette.textPrimary,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Haritada kulüp ara...',
                                    hintStyle: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 13,
                                      color: palette.textMuted,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(vertical: 11),
                                  ),
                                ),
                              ),
                              if (_isLoading)
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: palette.accent,
                                  ),
                                )
                              else
                                Text(
                                  '${_clubs.length}',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.monoFontFamily,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: palette.primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GlassCircleButton(
                        icon: _isLocating
                            ? Icons.hourglass_top_rounded
                            : Icons.my_location_rounded,
                        tooltip: 'Konumuma Git',
                        onTap: _centerOnUser,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Seçili Kulüp Alt Kartı
          if (_selectedClub != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24 + MediaQuery.of(context).padding.bottom,
              child: SoftGlassPanel(
                level: 1,
                borderRadius: BorderRadius.circular(18),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _selectedClub!.isSchool
                            ? Icons.school_rounded
                            : Icons.shield_rounded,
                        color: palette.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            StringUtils.toTitleCase(_selectedClub!.name),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (_selectedClub!.city != null)
                                StringUtils.toTitleCase(_selectedClub!.city!),
                              '${_selectedClub!.athleteCount} Sporcu',
                            ].join(' · '),
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_selectedClub!.id != null)
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ClubDetailScreen(
                                clubId: _selectedClub!.id!,
                                clubName: _selectedClub!.name,
                                repository: widget.repository,
                                onMeetSelected: widget.onMeetSelected,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: palette.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        child: const Text(
                          'Detay',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
