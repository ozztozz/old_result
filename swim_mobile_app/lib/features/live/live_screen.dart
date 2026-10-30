import 'package:flutter/material.dart';
import '../../data/repositories/swim_repository.dart';
import '../../data/models/live_meet.dart';
import 'live_meet_detail_screen.dart';

/// 4. Ekran: Canlı Yarış İzleyici (Live Viewer)
class LiveScreen extends StatefulWidget {
  final SwimRepository repository;

  const LiveScreen({super.key, required this.repository});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  bool _isLoading = true;
  List<LiveMeetSummary> _liveMeets = [];

  @override
  void initState() {
    super.initState();
    _loadLiveMeets();
  }

  Future<void> _loadLiveMeets() async {
    setState(() => _isLoading = true);
    try {
      final list = await widget.repository.getLiveMeets();
      if (mounted) {
        setState(() {
          _liveMeets = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openLiveDetail(LiveMeetSummary live) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveMeetDetailScreen(
          live: live,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.sensors, color: Colors.red),
            SizedBox(width: 8),
            Text('TYF Canlı Yarış Takibi'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _loadLiveMeets,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadLiveMeets,
              child: _liveMeets.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.pool, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text(
                            'Şu anda aktif bir canlı yarış bulunmuyor.',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Yeni bir TYF canlı yarış oturumu başladığında burada listelenecektir.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _liveMeets.length,
                      itemBuilder: (context, index) {
                        return _buildLiveCard(_liveMeets[index]);
                      },
                    ),
            ),
    );
  }

  Widget _buildLiveCard(LiveMeetSummary live) {
    final isRunning = live.status == 'ISLENIYOR';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openLiveDetail(live),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isRunning ? Colors.green.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isRunning ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          live.status,
                          style: TextStyle(
                            color: isRunning ? Colors.green.shade900 : Colors.grey.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (live.city.isNotEmpty)
                    Text(
                      live.city,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                live.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (live.date.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    live.date,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),

              // Start ve Sonuç İlerleme Çubukları
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Start Listesi: ${live.startListProgress.processed} / ${live.startListProgress.total}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: live.startListProgress.total > 0
                              ? live.startListProgress.processed / live.startListProgress.total
                              : 0,
                          backgroundColor: Colors.blue.shade100,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sonuç Listesi: ${live.resultListProgress.processed} / ${live.resultListProgress.total}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: live.resultListProgress.total > 0
                              ? live.resultListProgress.processed / live.resultListProgress.total
                              : 0,
                          backgroundColor: Colors.green.shade100,
                          color: Colors.green,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Tıklama Yönlendirme İpucu (Action Bar)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Yarışları ve Sonuçları Gör',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
