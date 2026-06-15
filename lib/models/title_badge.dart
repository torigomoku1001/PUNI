import 'package:flutter/material.dart';

class TitleBadge {
  final String id;
  final String name;
  final String description;
  final int tier; // 1: ブロンズ, 2: シルバー, 3: ゴールド, 4: プラチナ/ダイヤ
  final IconData icon;
  final Color color;

  const TitleBadge({
    required this.id,
    required this.name,
    required this.description,
    required this.tier,
    required this.icon,
    required this.color,
  });

  // 全称号のマスターデータ
  static const List<TitleBadge> allBadges = [
    // === 親密度 ===
    TitleBadge(id: 'intimacy_100', name: 'ともだち', description: '親密度100達成', tier: 1, icon: Icons.sentiment_satisfied, color: Colors.green),
    TitleBadge(id: 'intimacy_200', name: 'なかよし', description: '親密度200達成', tier: 1, icon: Icons.sentiment_very_satisfied, color: Colors.lightGreen),
    TitleBadge(id: 'intimacy_300', name: 'いつもいっしょ', description: '親密度300達成', tier: 2, icon: Icons.group, color: Colors.teal),
    TitleBadge(id: 'intimacy_400', name: 'ベストフレンド', description: '親密度400達成', tier: 2, icon: Icons.favorite_border, color: Colors.pinkAccent),
    TitleBadge(id: 'intimacy_500', name: 'ズッ友', description: '親密度500達成', tier: 3, icon: Icons.favorite, color: Colors.pink),
    TitleBadge(id: 'intimacy_1000', name: 'ソウルメイト', description: '親密度1000達成', tier: 3, icon: Icons.volunteer_activism, color: Colors.redAccent),
    TitleBadge(id: 'intimacy_3000', name: '運命の出会い', description: '親密度3000達成', tier: 4, icon: Icons.stars, color: Colors.red),
    TitleBadge(id: 'intimacy_5000', name: '永遠の絆', description: '親密度5000達成', tier: 4, icon: Icons.diamond, color: Colors.deepPurpleAccent),

    // === 歩数 ===
    TitleBadge(id: 'steps_1000', name: 'おさんぽ初心者', description: 'PUNIを入れてから1,000歩達成', tier: 1, icon: Icons.directions_walk, color: Colors.lightBlue),
    TitleBadge(id: 'steps_10000', name: 'おさんぽ日和', description: 'PUNIを入れてから1万歩達成', tier: 2, icon: Icons.directions_run, color: Colors.blue),
    TitleBadge(id: 'steps_100000', name: 'おさんぽ達人', description: 'PUNIを入れてから10万歩達成', tier: 3, icon: Icons.hiking, color: Colors.indigo),
    TitleBadge(id: 'steps_500000', name: '旅の仲間', description: 'PUNIを入れてから50万歩達成', tier: 4, icon: Icons.map, color: Colors.deepOrange),
    TitleBadge(id: 'steps_1000000', name: '地球一周', description: 'PUNIを入れてから100万歩達成', tier: 4, icon: Icons.public, color: Colors.blueAccent),

    // === レベル ===
    TitleBadge(id: 'level_10', name: 'ぷにビギナー', description: 'レベル10達成', tier: 1, icon: Icons.arrow_upward, color: Colors.lime),
    TitleBadge(id: 'level_30', name: 'ぷにルーキー', description: 'レベル30達成', tier: 2, icon: Icons.keyboard_double_arrow_up, color: Colors.cyan),
    TitleBadge(id: 'level_50', name: 'ぷにベテラン', description: 'レベル50達成', tier: 3, icon: Icons.military_tech, color: Colors.amber),
    TitleBadge(id: 'level_77', name: 'ラッキーぷに', description: 'レベル77達成', tier: 4, icon: Icons.casino, color: Colors.purpleAccent),
    TitleBadge(id: 'level_100', name: 'ぷにマスター', description: 'レベル100達成', tier: 4, icon: Icons.workspace_premium, color: Colors.orange),

    // === 消費エネルギー ===
    TitleBadge(id: 'energy_100', name: '元気いっぱい', description: 'ぷにエネルギーを合計100使った', tier: 1, icon: Icons.battery_charging_full, color: Colors.yellow),
    TitleBadge(id: 'energy_1000', name: 'あばれん坊', description: 'ぷにエネルギーを合計1,000使った', tier: 2, icon: Icons.bolt, color: Colors.orangeAccent),
    TitleBadge(id: 'energy_5000', name: 'エナジーの泉', description: 'ぷにエネルギーを合計5,000使った', tier: 3, icon: Icons.offline_bolt, color: Colors.deepOrangeAccent),
    TitleBadge(id: 'energy_7777', name: '奇跡のパワー', description: 'ぷにエネルギーを合計7,777使った', tier: 4, icon: Icons.electric_bolt, color: Colors.yellowAccent),
    TitleBadge(id: 'energy_10000', name: '限界突破', description: 'ぷにエネルギーを合計10,000使った', tier: 4, icon: Icons.flash_on, color: Colors.red),

    // === ご飯回数 ===
    TitleBadge(id: 'feed_10', name: 'はじめてのもぐもぐ', description: 'ご飯を10回あげた', tier: 1, icon: Icons.restaurant, color: Colors.brown),
    TitleBadge(id: 'feed_50', name: 'くいしんぼう', description: 'ご飯を50回あげた', tier: 2, icon: Icons.restaurant_menu, color: Colors.orange),
    TitleBadge(id: 'feed_77', name: 'ラッキーグルメ', description: 'ご飯を77回あげた', tier: 3, icon: Icons.set_meal, color: Colors.deepPurple),
    TitleBadge(id: 'feed_100', name: 'お腹いっぱい', description: 'ご飯を100回あげた', tier: 3, icon: Icons.fastfood, color: Colors.redAccent),
    TitleBadge(id: 'feed_500', name: '美食家', description: 'ご飯を500回あげた', tier: 4, icon: Icons.cake, color: Colors.pinkAccent),
    TitleBadge(id: 'feed_1000', name: '三ツ星シェフ', description: 'ご飯を1,000回あげた', tier: 4, icon: Icons.local_dining, color: Colors.amber),

    // === 動画視聴 ===
    TitleBadge(id: 'ad_5', name: 'TVキッズ', description: '動画を5回みた', tier: 1, icon: Icons.tv, color: Colors.grey),
    TitleBadge(id: 'ad_10', name: '動画ウォッチャー', description: '動画を10回みた', tier: 1, icon: Icons.ondemand_video, color: Colors.blueGrey),
    TitleBadge(id: 'ad_30', name: 'CM愛好家', description: '動画を30回みた', tier: 2, icon: Icons.live_tv, color: Colors.teal),
    TitleBadge(id: 'ad_50', name: 'シネマファン', description: '動画を50回みた', tier: 2, icon: Icons.theaters, color: Colors.indigoAccent),
    TitleBadge(id: 'ad_100', name: 'テレビっ子', description: '動画を100回みた', tier: 3, icon: Icons.smart_display, color: Colors.deepPurple),
    TitleBadge(id: 'ad_500', name: '動画マスター', description: '動画を500回みた', tier: 4, icon: Icons.movie, color: Colors.red),
    TitleBadge(id: 'ad_1000', name: 'スポンサーの星', description: '動画を1,000回みた', tier: 4, icon: Icons.star_rate, color: Colors.yellow),

    // === 累計コイン ===
    TitleBadge(id: 'coin_77777', name: '大富豪', description: '総獲得コイン数77,777コイン達成', tier: 4, icon: Icons.monetization_on, color: Colors.amber),
  ];
}
