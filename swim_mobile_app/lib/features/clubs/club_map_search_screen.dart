import 'dart:async';
import 'dart:math' as math;
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
    _centerOnUser(silent: true);
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

  Future<void> _centerOnUser({bool silent = false}) async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!silent && mounted) {
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
        if (!silent && mounted) {
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
      _mapController.move(point, 12.5);
    } catch (_) {
      if (!silent && mounted) {
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
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: (_, __) => setState(() => _selectedClub = null),
              onPositionChanged: (camera, _) {
                final z = camera.zoom;
                final crossedCluster = (z >= 10.5) != (_currentZoom >= 10.5);
                final crossedLabel = (z >= 13) != (_currentZoom >= 13);
                final clusterZoomStep =
                    z < 10.5 && z.floor() != _currentZoom.floor();
                final labelZoomStep =
                    z >= 13 && (z - _currentZoom).abs() >= 0.4;
                if (crossedCluster ||
                    crossedLabel ||
                    clusterZoomStep ||
                    labelZoomStep) {
                  setState(() => _currentZoom = z);
                } else {
                  _currentZoom = z;
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: palette.isDark
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}'
                    : 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.kulvar.swim_mobile_app',
              ),
              TileLayer(
                urlTemplate: palette.isDark
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}'
                    : 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
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
                          color: palette.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: palette.surface,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: palette.primary.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ..._buildClubMarkers(palette),
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
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
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
                      FilledButton(
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
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.accent,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.buttonRadius,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.s12,
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

  String _shortClubName(String rawName) {
    final formatted = StringUtils.toTitleCase(rawName);
    final stripped = formatted
        .replaceAll(
          RegExp(
            r'(?:^|\s)(Gençlik\s+Ve\s+Spor\s+Kulübü\s+Derneği|Gençlik\s+Ve\s+Spor\s+Kulübü|Yüzme\s+İhtisas\s+Spor\s+Kulübü|İhtisas\s+Spor\s+Kulübü|Su\s+Sporları\s+Kulübü|Spor\s+Kulübü\s+Derneği|Spor\s+Kulübü|Spor\s+Klübü|Kulübü\s+Derneği|Kulübü|Klübü|Derneği|Gsk|Sk)(?=\s|$)',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return stripped.isNotEmpty ? stripped : formatted;
  }

  List<Marker> _buildClubMarkers(AppColorPalette palette) {
    final validClubs = _clubs
        .where((c) => c.latitude != null && c.longitude != null)
        .toList();
    if (validClubs.isEmpty) return const [];

    // Uzak zoom seviyesinde yakın kulüpleri tek küme balonunda birleştir
    if (_currentZoom < 10.5) {
      final cellSize = 0.08 * math.pow(2, (10.5 - _currentZoom).clamp(0, 5));
      final buckets = <String, List<ClubSearchItem>>{};
      for (final club in validClubs) {
        final gx = (club.latitude! / cellSize).floor();
        final gy = (club.longitude! / cellSize).floor();
        buckets.putIfAbsent('$gx:$gy', () => []).add(club);
      }

      final markers = <Marker>[];
      for (final group in buckets.values) {
        if (group.length == 1) {
          final club = group.first;
          markers.add(
            _buildSingleClubMarker(
              palette: palette,
              club: club,
              point: LatLng(club.latitude!, club.longitude!),
            ),
          );
        } else {
          final avgLat =
              group.map((c) => c.latitude!).reduce((a, b) => a + b) /
                  group.length;
          final avgLng =
              group.map((c) => c.longitude!).reduce((a, b) => a + b) /
                  group.length;
          final center = LatLng(avgLat, avgLng);
          markers.add(
            Marker(
              point: center,
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: () {
                  _mapController.move(
                    center,
                    (_currentZoom + 2.5).clamp(5.0, 14.0),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.secondary,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.surface, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: palette.shadowTint.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${group.length}',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }
      return markers;
    }

    // Yakın zoom seviyesinde aynı/çok yakın konumdaki pinleri dairesel dağıt
    const overlapCell = 0.0012;
    final overlapGroups = <String, List<ClubSearchItem>>{};
    for (final club in validClubs) {
      final gx = (club.latitude! / overlapCell).round();
      final gy = (club.longitude! / overlapCell).round();
      overlapGroups.putIfAbsent('$gx:$gy', () => []).add(club);
    }

    final placedPins = <({ClubSearchItem club, LatLng point, Offset px})>[];
    for (final group in overlapGroups.values) {
      if (group.length == 1) {
        final club = group.first;
        final pt = LatLng(club.latitude!, club.longitude!);
        placedPins.add((
          club: club,
          point: pt,
          px: _latLngToPixel(pt, _currentZoom),
        ));
      } else {
        for (var i = 0; i < group.length; i++) {
          final club = group[i];
          final ring = i ~/ 8;
          final countInRing = math.min(group.length - ring * 8, 8);
          final angle = (2 * math.pi * (i % 8)) / countInRing;
          final radius = 0.0009 * (1 + ring * 0.75);
          final offsetPoint = LatLng(
            club.latitude! + radius * math.sin(angle),
            club.longitude! + radius * math.cos(angle),
          );
          placedPins.add((
            club: club,
            point: offsetPoint,
            px: _latLngToPixel(offsetPoint, _currentZoom),
          ));
        }
      }
    }

    // Seçili kulübü en sona alarak hem etiket önceliği hem de en üstte çizim sağla
    placedPins.sort((a, b) {
      final aSel = _selectedClub?.id == a.club.id ? 1 : 0;
      final bSel = _selectedClub?.id == b.club.id ? 1 : 0;
      return aSel.compareTo(bSel);
    });

    // Piksel bazlı çakışma kontrolü: hiçbir etiket başka bir pini veya etiketi örtmesin
    final occupied = <Rect>[
      for (final item in placedPins)
        Rect.fromCenter(center: item.px, width: 28, height: 28),
    ];

    final labelPlacements = <ClubSearchItem, _LabelSide>{};
    for (final item in placedPins.reversed) {
      final isSelected = _selectedClub?.id == item.club.id;
      if (!isSelected && _currentZoom < 13) {
        labelPlacements[item.club] = _LabelSide.none;
        continue;
      }
      final labelText = _shortClubName(item.club.name);
      final estWidth = (labelText.length * 6.4 + 16).clamp(56.0, 148.0);
      const estHeight = 22.0;
      final pinHalf = isSelected ? 20.0 : 16.0;

      if (isSelected) {
        labelPlacements[item.club] = _LabelSide.right;
        occupied.add(
          Rect.fromLTWH(
            item.px.dx + pinHalf + 6,
            item.px.dy - estHeight / 2,
            estWidth,
            estHeight,
          ),
        );
        continue;
      }

      final candidates = [
        (
          side: _LabelSide.right,
          rect: Rect.fromLTWH(
            item.px.dx + pinHalf + 6,
            item.px.dy - estHeight / 2,
            estWidth,
            estHeight,
          ),
        ),
        (
          side: _LabelSide.top,
          rect: Rect.fromLTWH(
            item.px.dx - estWidth / 2,
            item.px.dy - pinHalf - 4 - estHeight,
            estWidth,
            estHeight,
          ),
        ),
        (
          side: _LabelSide.left,
          rect: Rect.fromLTWH(
            item.px.dx - pinHalf - 6 - estWidth,
            item.px.dy - estHeight / 2,
            estWidth,
            estHeight,
          ),
        ),
        (
          side: _LabelSide.bottom,
          rect: Rect.fromLTWH(
            item.px.dx - estWidth / 2,
            item.px.dy + pinHalf + 4,
            estWidth,
            estHeight,
          ),
        ),
      ];

      _LabelSide chosen = _LabelSide.none;
      for (final candidate in candidates) {
        final overlaps = occupied.any((r) => r.overlaps(candidate.rect));
        if (!overlaps) {
          chosen = candidate.side;
          occupied.add(candidate.rect);
          break;
        }
      }
      labelPlacements[item.club] = chosen;
    }

    return [
      for (final item in placedPins)
        _buildSingleClubMarker(
          palette: palette,
          club: item.club,
          point: item.point,
          labelSide: labelPlacements[item.club] ?? _LabelSide.none,
        ),
    ];
  }

  Offset _latLngToPixel(LatLng point, double zoom) {
    final scale = 256.0 * math.pow(2.0, zoom);
    final x = (point.longitude + 180.0) / 360.0 * scale;
    final siny =
        math.sin(point.latitude * math.pi / 180.0).clamp(-0.9999, 0.9999);
    final y =
        (0.5 - math.log((1.0 + siny) / (1.0 - siny)) / (4.0 * math.pi)) *
            scale;
    return Offset(x, y);
  }

  Marker _buildSingleClubMarker({
    required AppColorPalette palette,
    required ClubSearchItem club,
    required LatLng point,
    _LabelSide labelSide = _LabelSide.none,
  }) {
    final isSelected = _selectedClub?.id == club.id;
    final pinColor = isSelected
        ? palette.accent
        : (club.isSchool ? palette.infoCyan : palette.primary);
    final size = isSelected ? 40.0 : 32.0;
    final labelText = _shortClubName(club.name);

    final Widget? labelWidget = labelSide == _LabelSide.none
        ? null
        : ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: palette.surface.withValues(alpha: 0.94),
                borderRadius: AppRadius.small,
                border: Border.all(
                  color: isSelected ? palette.accent : palette.border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadowTint.withValues(alpha: 0.14),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                labelText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
            ),
          );

    return Marker(
      point: point,
      width: size,
      height: size,
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedClub = club);
          _mapController.move(
            point,
            _mapController.camera.zoom < 12 ? 12.5 : _mapController.camera.zoom,
          );
        },
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Transform.rotate(
              angle: -math.pi / 4,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: pinColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(999),
                    topRight: Radius.circular(999),
                    bottomRight: Radius.circular(999),
                    bottomLeft: Radius.circular(4),
                  ),
                  border: Border.all(
                    color: palette.surface,
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: palette.shadowTint.withValues(
                        alpha: isSelected ? 0.32 : 0.22,
                      ),
                      blurRadius: isSelected ? 10 : 6,
                      offset: const Offset(-2, 3),
                    ),
                  ],
                ),
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Icon(
                    club.isSchool ? Icons.school_rounded : Icons.shield_rounded,
                    size: isSelected ? 18 : 14,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
            if (labelWidget != null && labelSide == _LabelSide.right)
              Positioned(left: size + 6, child: labelWidget),
            if (labelWidget != null && labelSide == _LabelSide.left)
              Positioned(right: size + 6, child: labelWidget),
            if (labelWidget != null && labelSide == _LabelSide.top)
              Positioned(bottom: size + 4, child: labelWidget),
            if (labelWidget != null && labelSide == _LabelSide.bottom)
              Positioned(top: size + 4, child: labelWidget),
          ],
        ),
      ),
    );
  }
}

enum _LabelSide { none, right, top, left, bottom }
