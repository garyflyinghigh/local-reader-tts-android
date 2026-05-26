import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/book.dart';

class BookStorageService {
  static const _booksKey = 'bookshelf.books.v1';

  Future<List<Book>> loadBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_booksKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }

    return decoded
        .whereType<Map>()
        .map((item) => Book.fromJson(Map<String, Object?>.from(item)))
        .where((book) => book.id.isNotEmpty && book.path.isNotEmpty)
        .toList(growable: false)
      ..sort(_compareLastOpenedDesc);
  }

  Future<void> upsertBook(Book book) async {
    final books = await loadBooks();
    final next = [
      book.copyWith(lastOpenedAt: book.lastOpenedAt ?? DateTime.now()),
      for (final existing in books)
        if (existing.id != book.id) existing,
    ]..sort(_compareLastOpenedDesc);
    await _saveBooks(next);
  }

  Future<void> updateReadingState({
    required String bookId,
    required int chapterIndex,
    required double scrollProgress,
    required int ttsSentenceIndex,
    bool touchLastOpened = true,
  }) async {
    final books = await loadBooks();
    final next = [
      for (final book in books)
        if (book.id == bookId)
          book.copyWith(
            currentChapterIndex: chapterIndex,
            progress: scrollProgress.clamp(0.0, 1.0),
            ttsSentenceIndex: ttsSentenceIndex < 0 ? 0 : ttsSentenceIndex,
            lastOpenedAt: touchLastOpened ? DateTime.now() : book.lastOpenedAt,
          )
        else
          book,
    ]..sort(_compareLastOpenedDesc);
    await _saveBooks(next);
  }

  Future<void> touchBook(String bookId) async {
    final books = await loadBooks();
    final next = [
      for (final book in books)
        if (book.id == bookId)
          book.copyWith(lastOpenedAt: DateTime.now())
        else
          book,
    ]..sort(_compareLastOpenedDesc);
    await _saveBooks(next);
  }

  Future<void> deleteBook(String bookId) async {
    final books = await loadBooks();
    await _saveBooks(
      books.where((book) => book.id != bookId).toList(growable: false),
    );
  }

  Future<void> _saveBooks(List<Book> books) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _booksKey,
      jsonEncode(books.map((book) => book.toJson()).toList()),
    );
  }

  static int _compareLastOpenedDesc(Book a, Book b) {
    final aTime = a.lastOpenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.lastOpenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bTime.compareTo(aTime);
  }
}
