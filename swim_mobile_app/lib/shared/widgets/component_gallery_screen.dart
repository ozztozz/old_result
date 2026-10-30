import 'package:flutter/material.dart';
import '../../core/theme/swim_theme.dart';
import '../../data/models/race_result.dart';
import 'swim_status_badge.dart';
import 'swim_result_card.dart';

/// Bileşen Galerisi Ekranı (Component Gallery / Design System Showcase)
/// Tüm tasarım sistemi bileşenlerini, renklerini, rozetlerini ve dinamik font taşma testlerini tek yerde sunar.
class ComponentGalleryScreen extends StatefulWidget {
  const ComponentGalleryScreen({super.key});

  @override
  State<ComponentGalleryScreen> createState() => _ComponentGalleryScreenState();
}

class _ComponentGalleryScreenState extends State<ComponentGalleryScreen> {
  double _textScaleFactor = 1.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.swimColors;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_textScaleFactor)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SwimDesign Bileşen Galerisi'),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('WCAG AA Uyumlu Yüzme Tasarım Sistemi')),
                );
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Dinamik Yazı Boyutu Testi (Accessibility Slider)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Yazı Boyutu Ölçeği (Erişilebilirlik)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '%${(_textScaleFactor * 100).toInt()}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                      ],
                    ),
                    Slider(
                      value: _textScaleFactor,
                      min: 0.8,
                      max: 1.6,
                      divisions: 8,
                      label: '%${(_textScaleFactor * 100).toInt()}',
                      onChanged: (val) => setState(() => _textScaleFactor = val),
                    ),
                    const Text(
                      'Sürelerin ve kartların büyük fontta taşmadığını (FittedBox) test edin.',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. İmza Süre Tipografisi (timeDisplay)
            const Text('1. İmza Süre Tipografisi (Tabular Figures)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('00:24.85  (1. Kulvar)', style: SwimTheme.timeDisplay),
                    const SizedBox(height: 4),
                    Text('01:02.14  (2. Kulvar)', style: SwimTheme.timeDisplay),
                    const SizedBox(height: 4),
                    Text('15:48.92  (1500m)', style: SwimTheme.timeDisplay),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 3. Durum Rozetleri
            const Text('2. Durum Rozetleri (İkon + Etiket)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SwimStatusBadge.finished(),
                SwimStatusBadge.waiting(),
                SwimStatusBadge.disqualified(),
                SwimStatusBadge.pb(),
                SwimStatusBadge.standard(badge: 'A1'),
                SwimStatusBadge.standard(badge: 'B2'),
                SwimStatusBadge.provisional(),
              ],
            ),
            const SizedBox(height: 20),

            // 4. Madalya Renkleri (Kürsü)
            const Text('3. Kürsü Madalya Renkleri', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildMedalBox('1. Sıra (Altın)', colors.medalGold),
                const SizedBox(width: 8),
                _buildMedalBox('2. Sıra (Gümüş)', colors.medalSilver),
                const SizedBox(width: 8),
                _buildMedalBox('3. Sıra (Bronz)', colors.medalBronze),
              ],
            ),
            const SizedBox(height: 20),

            // 5. Örnek Sonuç Kartları
            const Text('4. Sonuç Kartları (FittedBox Taşma Korumalı)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            SwimResultCard(
              result: RaceResult(
                id: 1,
                eventNo: '1',
                distance: 50,
                stroke: 'free',
                strokeLabel: 'Serbest',
                heat: 'Seri 4',
                lane: 4,
                rank: '1',
                time: '00:24.85',
                timeCs: 2485,
                resultStatus: 'OK',
                points: 620,
                qualifyingStandard: QualifyingStandard(passed: true, badge: 'A1'),
                source: 'official',
                athleteId: 101,
                athleteName: 'Ahmet Yılmaz',
                clubName: 'Fenerbahçe Spor Kulübü',
              ),
            ),
            SwimResultCard(
              result: RaceResult(
                id: 2,
                eventNo: '1',
                distance: 50,
                stroke: 'free',
                strokeLabel: 'Serbest',
                heat: 'Seri 4',
                lane: 5,
                rank: '2',
                time: '00:25.12',
                timeCs: 2512,
                resultStatus: 'OK',
                points: 595,
                qualifyingStandard: QualifyingStandard(passed: true, badge: 'A2'),
                source: 'official',
                athleteId: 102,
                athleteName: 'Mehmet Demir',
                clubName: 'Galatasaray Spor Kulübü',
              ),
            ),
            SwimResultCard(
              result: RaceResult(
                id: 3,
                eventNo: '1',
                distance: 50,
                stroke: 'free',
                strokeLabel: 'Serbest',
                heat: 'Seri 3',
                lane: 2,
                rank: '3',
                time: '00:25.90',
                timeCs: 2590,
                resultStatus: 'OK',
                points: 540,
                qualifyingStandard: QualifyingStandard(passed: true, badge: 'B1'),
                source: 'official',
                athleteId: 103,
                athleteName: 'Can Öztürk',
                clubName: 'Enka Spor Kulübü',
              ),
            ),
            SwimResultCard(
              result: RaceResult(
                id: 4,
                eventNo: '1',
                distance: 50,
                stroke: 'free',
                strokeLabel: 'Serbest',
                heat: 'Seri 5',
                lane: 3,
                rank: '',
                resultStatus: 'WAITING',
                source: 'live',
                athleteId: 104,
                athleteName: 'Barış Deniz',
                clubName: 'Ankara Yüzme Kulübü',
              ),
            ),
            SwimResultCard(
              result: RaceResult(
                id: 5,
                eventNo: '1',
                distance: 50,
                stroke: 'free',
                strokeLabel: 'Serbest',
                heat: 'Seri 2',
                lane: 6,
                rank: 'DQ',
                resultStatus: 'DQ',
                source: 'official',
                athleteId: 105,
                athleteName: 'Kemal Aksoy',
                clubName: 'Ferdi Sporcu',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedalBox(String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 1),
        ),
        child: Column(
          children: [
            Icon(Icons.emoji_events, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
