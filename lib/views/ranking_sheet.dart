import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/creature_state.dart';
import '../services/ranking_service.dart';

class RankingSheet extends StatefulWidget {
  final CreatureState state;
  final Color primaryColor;

  const RankingSheet({
    super.key,
    required this.state,
    required this.primaryColor,
  });

  @override
  State<RankingSheet> createState() => _RankingSheetState();
}

class _RankingSheetState extends State<RankingSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final RankingService _rankingService = RankingService();
  
  bool _isLoading = true;
  String _myPlayerId = '';

  List<RankingEntry> _intimacyRankings = [];
  List<RankingEntry> _levelRankings = [];
  List<RankingEntry> _coinsRankings = [];

  int _myIntimacyRank = -1;
  int _myLevelRank = -1;
  int _myCoinsRank = -1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    // 自分の最新スコアをFirebaseに同期
    await widget.state.syncRankings();

    _myPlayerId = await _rankingService.getPlayerId();

    // 全カテゴリのランキングを並行して取得
    final results = await Future.wait([
      _rankingService.getTopRankings('intimacy'),
      _rankingService.getTopRankings('level'),
      _rankingService.getTopRankings('coins'),
      _rankingService.getMyRank('intimacy', widget.state.intimacy),
      _rankingService.getMyRank('level', widget.state.level.toDouble()),
      _rankingService.getMyRank('coins', widget.state.totalDroppedCoins.toDouble()),
    ]);

    if (mounted) {
      setState(() {
        _intimacyRankings = results[0] as List<RankingEntry>;
        _levelRankings = results[1] as List<RankingEntry>;
        _coinsRankings = results[2] as List<RankingEntry>;
        
        _myIntimacyRank = results[3] as int;
        _myLevelRank = results[4] as int;
        _myCoinsRank = results[5] as int;

        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildMedal(int rank) {
    if (rank == 1) {
      return const Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 32);
    } else if (rank == 2) {
      return const Icon(Icons.workspace_premium, color: Color(0xFFC0C0C0), size: 32);
    } else if (rank == 3) {
      return const Icon(Icons.workspace_premium, color: Color(0xFFCD7F32), size: 32);
    } else {
      return Container(
        width: 32,
        alignment: Alignment.center,
        child: Text(
          '$rank',
          style: GoogleFonts.notoSansJp(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        ),
      );
    }
  }

  Widget _buildRankingList(List<RankingEntry> rankings, String category, int myRank, double myScore) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (rankings.isEmpty) {
      return Center(
        child: Text(
          'まだデータがありません',
          style: GoogleFonts.notoSansJp(color: Colors.grey),
        ),
      );
    }

    String formatScoreText(double score) {
      if (category == 'level') {
        return 'Lv ${score.toInt()}';
      } else if (category == 'coins') {
        return '${score.toInt()} 枚';
      } else {
        return '${score.toStringAsFixed(1)} pt';
      }
    }

    return Column(
      children: [
        // 自分の順位ハイライト
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [widget.primaryColor.withOpacity(0.8), widget.primaryColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: widget.primaryColor.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Text(
                myRank > 0 ? '$myRank位' : '-位',
                style: GoogleFonts.notoSansJp(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'あなた (${widget.state.playerName})',
                      style: GoogleFonts.notoSansJp(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.state.puniName,
                      style: GoogleFonts.notoSansJp(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                formatScoreText(myScore),
                style: GoogleFonts.notoSansJp(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ランキングリスト
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: rankings.length,
            itemBuilder: (context, index) {
              final entry = rankings[index];
              final isMe = entry.playerId == _myPlayerId;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMe 
                      ? widget.primaryColor.withOpacity(0.1) 
                      : (isDark ? Colors.grey.shade900 : Colors.white),
                  borderRadius: BorderRadius.circular(16),
                  border: isMe ? Border.all(color: widget.primaryColor, width: 2) : null,
                  boxShadow: isMe ? null : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _buildMedal(index + 1),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.playerName,
                            style: GoogleFonts.notoSansJp(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isMe ? widget.primaryColor : theme.textTheme.bodyLarge?.color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            entry.puniName,
                            style: GoogleFonts.notoSansJp(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatScoreText(entry.score),
                      style: GoogleFonts.notoSansJp(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.grey.shade100,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // ハンドルバー
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 48,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.4),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          // タイトル
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.emoji_events, color: widget.primaryColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  'ランキング',
                  style: GoogleFonts.notoSansJp(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                const Spacer(),
                if (_isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(widget.primaryColor),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loadData,
                    color: Colors.grey,
                  ),
              ],
            ),
          ),
          // タブバー
          TabBar(
            controller: _tabController,
            labelColor: widget.primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: widget.primaryColor,
            indicatorWeight: 3,
            labelStyle: GoogleFonts.notoSansJp(fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: '親密度'),
              Tab(text: 'レベル'),
              Tab(text: 'ドロップコイン'),
            ],
          ),
          // タブコンテンツ
          Expanded(
            child: _isLoading && _intimacyRankings.isEmpty
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(widget.primaryColor),
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildRankingList(_intimacyRankings, 'intimacy', _myIntimacyRank, widget.state.intimacy),
                      _buildRankingList(_levelRankings, 'level', _myLevelRank, widget.state.level.toDouble()),
                      _buildRankingList(_coinsRankings, 'coins', _myCoinsRank, widget.state.totalDroppedCoins.toDouble()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
