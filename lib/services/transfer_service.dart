import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TransferCode {
  final String id;
  final String password;

  TransferCode(this.id, this.password);
}

class TransferService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collectionName = 'transfer_data';

  String _generateRandomString(int length, {bool numbersOnly = false}) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    const numbers = '0123456789';
    final random = Random();
    final source = numbersOnly ? numbers : chars;
    return String.fromCharCodes(Iterable.generate(
      length,
      (_) => source.codeUnitAt(random.nextInt(source.length)),
    ));
  }

  Future<String> _exportData() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> data = {};
    for (final key in prefs.getKeys()) {
      if (key.startsWith('puni_')) {
        data[key] = prefs.get(key);
      }
    }
    return jsonEncode(data);
  }

  Future<void> _importData(String jsonString) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> data = jsonDecode(jsonString);
    
    // Clear all existing puni_ keys before importing to ensure a clean state
    for (final key in prefs.getKeys()) {
      if (key.startsWith('puni_')) {
        await prefs.remove(key);
      }
    }

    // Write new data
    for (final key in data.keys) {
      final value = data[key];
      if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, List<String>.from(value));
      }
    }
  }

  Future<TransferCode> issueTransferCode() async {
    // 8文字の英数字ID、6文字の数字パスワード
    final id = _generateRandomString(8);
    final password = _generateRandomString(6, numbersOnly: true);

    final dataJson = await _exportData();

    await _firestore.collection(_collectionName).doc(id).set({
      'password': password,
      'data': dataJson,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return TransferCode(id, password);
  }

  Future<bool> transferData(String id, String password) async {
    final doc = await _firestore.collection(_collectionName).doc(id.toUpperCase()).get();

    if (!doc.exists) {
      throw Exception('引き継ぎIDが見つかりません。');
    }

    final dataMap = doc.data();
    if (dataMap == null) {
      throw Exception('データが破損しています。');
    }

    final savedPassword = dataMap['password'] as String?;
    if (savedPassword != password) {
      throw Exception('パスワードが間違っています。');
    }

    final dataJson = dataMap['data'] as String?;
    if (dataJson == null) {
      throw Exception('セーブデータが見つかりません。');
    }

    // データをローカルに展開
    await _importData(dataJson);
    return true;
  }
}
