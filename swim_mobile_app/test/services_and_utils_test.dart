import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swim_mobile_app/core/services/favorite_athletes_service.dart';
import 'package:swim_mobile_app/core/services/selected_club_service.dart';
import 'package:swim_mobile_app/core/utils/race_result_sorter.dart';
import 'package:swim_mobile_app/core/utils/string_utils.dart';
import 'package:swim_mobile_app/data/models/race_result.dart';

RaceResult _makeResult({
  required int id,
  String heat = '1',
  int? lane = 1,
  String rank = '',
  String? time,
  int? timeCs,
  String resultStatus = 'OK',
}) {
  return RaceResult(
    id: id,
    eventNo: '1',
    stroke: 'Freestyle',
    strokeLabel: 'Serbest',
    heat: heat,
    lane: lane,
    rank: rank,
    time: time,
    timeCs: timeCs,
    resultStatus: resultStatus,
    source: 'live',
    athleteId: id,
    athleteName: 'Sporcu $id',
    clubName: 'Test SK',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StringUtils.toTitleCase', () {
    test('handles Turkish characters properly', () {
      expect(StringUtils.toTitleCase('İSTANBUL YÜZME KULÜBÜ'), 'İstanbul Yüzme Kulübü');
      expect(StringUtils.toTitleCase('ısparta il birinciliği'), 'Isparta İl Birinciliği');
      expect(StringUtils.toTitleCase('ŞAMPİYONA'), 'Şampiyona');
    });
  });

  group('SelectedClubService', () {
    test('matches club names tolerantly with Turkish characters and suffixes', () async {
      SharedPreferences.setMockInitialValues({});
      await SelectedClubService.instance.init();
      await SelectedClubService.instance.setClub(id: 10, name: 'Fenerbahçe Spor Kulübü');

      expect(SelectedClubService.instance.matches('FENERBAHCE SK'), isTrue);
      expect(SelectedClubService.instance.matches('Farklı Kulüp', 10), isTrue);
      expect(SelectedClubService.instance.matches('Galatasaray SK', 20), isFalse);

      await SelectedClubService.instance.clearClub();
      expect(SelectedClubService.instance.hasSelectedClub, isFalse);
    });
  });

  group('FavoriteAthletesService', () {
    test('toggles, persists and removes favorite athlete IDs', () async {
      SharedPreferences.setMockInitialValues({});
      final service = FavoriteAthletesService.instance;
      await service.init();
      await service.clearAll();

      expect(service.isFavorite(42), isFalse);

      final added = await service.toggleFavorite(42);
      expect(added, isTrue);
      expect(service.isFavorite(42), isTrue);
      expect(service.favoriteIds, [42]);

      await service.removeFavorite(42);
      expect(service.isFavorite(42), isFalse);
      expect(service.isEmpty, isTrue);
    });
  });

  group('RaceResultSorter', () {
    test('orders finished by rank/time, then pending, then DQ/DNS/DNF at the end', () {
      final dq = _makeResult(id: 1, heat: '1', lane: 2, rank: 'DQ', resultStatus: 'DQ');
      final pending = _makeResult(id: 2, heat: '2', lane: 4, resultStatus: 'WAITING');
      final second = _makeResult(id: 3, heat: '3', lane: 3, rank: '2', time: '29.10', timeCs: 2910);
      final first = _makeResult(id: 4, heat: '3', lane: 5, rank: '1', time: '28.45', timeCs: 2845);

      final list = [dq, pending, second, first];
      RaceResultSorter.sort(list);

      expect(list.map((r) => r.id).toList(), [4, 3, 2, 1]);
    });
  });
}
