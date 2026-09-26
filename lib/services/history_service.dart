import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_item.dart';
import '../models/ask_response.dart';
import '../utils/error_handler.dart';

class HistoryService {
  HistoryService._();

  static final HistoryService instance = HistoryService._();
  static const String _key = 'solution_history';
  static const int maxCount = 20;

  Future<List<HistoryItem>> getHistory() async {
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final List<HistoryItem> items = <HistoryItem>[];
      for (final String raw
          in preferences.getStringList(_key) ?? <String>[]) {
        try {
          final dynamic decoded = jsonDecode(raw);
          if (decoded is Map) {
            items.add(HistoryItem.fromJson(Map<String, dynamic>.from(decoded)));
          }
        } on FormatException {
          // 单条数据损坏时跳过，保留其他历史记录。
        }
      }
      items.sort((HistoryItem a, HistoryItem b) =>
          b.createdAt.compareTo(a.createdAt));
      return items.take(maxCount).toList();
    } catch (error) {
      throw ErrorHandler.toAppException(error);
    }
  }

  Future<void> addHistory({
    required String id,
    required String imagePath,
    required AskResponse response,
    required Map<String, num> cropBox,
    required int rotationDegrees,
  }) async {
    try {
      final String savedPath = await _copyImage(id, imagePath);
      final List<HistoryItem> items = await getHistory();
      items.removeWhere((HistoryItem item) => item.id == id);
      items.insert(
        0,
        HistoryItem(
          id: id,
          imagePath: savedPath,
          finalAnswer: response.finalAnswer,
          createdAt: DateTime.now(),
          response: response,
          cropBox: Map<String, num>.from(cropBox),
          rotationDegrees: rotationDegrees,
        ),
      );
      final List<HistoryItem> removed = items.skip(maxCount).toList();
      final List<HistoryItem> retained = items.take(maxCount).toList();
      await _save(retained);
      for (final HistoryItem item in removed) {
        if (!retained.any(
          (HistoryItem retainedItem) =>
              retainedItem.imagePath == item.imagePath,
        )) {
          await _deleteFile(item.imagePath);
        }
      }
    } catch (error) {
      throw ErrorHandler.toAppException(error);
    }
  }

  Future<void> deleteHistory(String id) async {
    try {
      final List<HistoryItem> items = await getHistory();
      final List<HistoryItem> removed =
          items.where((HistoryItem item) => item.id == id).toList();
      items.removeWhere((HistoryItem item) => item.id == id);
      await _save(items);
      for (final HistoryItem item in removed) {
        await _deleteFile(item.imagePath);
      }
    } catch (error) {
      throw ErrorHandler.toAppException(error);
    }
  }

  Future<void> clearHistory() async {
    try {
      final List<HistoryItem> items = await getHistory();
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      await preferences.remove(_key);
      for (final String path
          in items.map((HistoryItem item) => item.imagePath).toSet()) {
        await _deleteFile(path);
      }
    } catch (error) {
      throw ErrorHandler.toAppException(error);
    }
  }

  Future<void> _save(List<HistoryItem> items) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await preferences.setStringList(
      _key,
      items
          .map((HistoryItem item) => jsonEncode(item.toJson()))
          .toList(),
    );
  }

  Future<String> _copyImage(String id, String sourcePath) async {
    final File source = File(sourcePath);
    if (!await source.exists()) {
      throw const AppException('题目图片不存在，无法保存历史记录。');
    }
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(
      '${documents.path}${Platform.pathSeparator}history_images',
    );
    await directory.create(recursive: true);
    final String safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final String destination =
        '${directory.path}${Platform.pathSeparator}$safeId.jpg';
    await source.copy(destination);
    return destination;
  }

  Future<void> _deleteFile(String path) async {
    if (path.isEmpty) return;
    final File file = File(path);
    if (await file.exists()) await file.delete();
  }
}
