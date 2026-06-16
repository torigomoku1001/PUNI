import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RankingEntry {
  final String playerId;
  final String playerName;
  final String puniName;
  final double score;

  RankingEntry({
    required this.playerId,
    required this.playerName,
    required this.puniName,
    required this.score,
  });

  factory RankingEntry.fromFirestore(Map<String, dynamic> data) {
    return RankingEntry(
      playerId: data['playerId'] ?? '',
      playerName: data['playerName'] ?? 'ななし',
      puniName: data['puniName'] ?? 'ななしPUNI',
      score: (data['score'] ?? 0).toDouble(),
    );
  }
}

class RankingService {
  static final RankingService _instance = RankingService._internal();
  factory RankingService() => _instance;
  RankingService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _cachedPlayerId;

  Future<String> getPlayerId() async {
    if (_cachedPlayerId != null) return _cachedPlayerId!;
    
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('ranking_player_id');
    if (id == null) {
      // Generate a random ID
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final rnd = Random();
      id = String.fromCharCodes(Iterable.generate(
        16, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
      await prefs.setString('ranking_player_id', id);
    }
    _cachedPlayerId = id;
    return id;
  }

  // スコアを同期
  Future<void> syncScore({
    required String category,
    required double score,
    required String playerName,
    required String puniName,
  }) async {
    try {
      final pid = await getPlayerId();
      final collection = _firestore.collection('rankings_$category');
      
      await collection.doc(pid).set({
        'playerId': pid,
        'playerName': playerName,
        'puniName': puniName,
        'score': score,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error syncing score for $category: $e");
    }
  }

  // ランキング取得 (上位50件)
  Future<List<RankingEntry>> getTopRankings(String category) async {
    try {
      final snapshot = await _firestore
          .collection('rankings_$category')
          .orderBy('score', descending: true)
          .limit(50)
          .get();

      return snapshot.docs
          .map((doc) => RankingEntry.fromFirestore(doc.data()))
          .toList();
    } catch (e) {
      debugPrint("Error fetching rankings for $category: $e");
      return [];
    }
  }

  // 自分の順位を取得（簡易計算）
  Future<int> getMyRank(String category, double myScore) async {
    try {
      // 自分よりスコアが高いドキュメントの数を数える
      final query = await _firestore
          .collection('rankings_$category')
          .where('score', isGreaterThan: myScore)
          .count()
          .get();
      return (query.count ?? 0) + 1;
    } catch (e) {
      debugPrint("Error fetching my rank for $category: $e");
      return -1;
    }
  }
}
