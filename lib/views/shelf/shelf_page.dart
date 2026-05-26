import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/book.dart';
import '../../services/database/book_storage_provider.dart';
import '../../services/database/book_storage_service.dart';
import '../../services/parser/book_parser_service.dart';
import '../reader/reader_view.dart';

final bookParserProvider = Provider<BookParserService>((ref) {
  return BookParserService();
});

final shelfBooksProvider =
    StateNotifierProvider<ShelfBooksController, AsyncValue<List<Book>>>((ref) {
  return ShelfBooksController(ref.read(bookStorageProvider));
});

class ShelfBooksController extends StateNotifier<AsyncValue<List<Book>>> {
  ShelfBooksController(this._storage) : super(const AsyncValue.loading()) {
    load();
  }

  final BookStorageService _storage;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _storage.loadBooks());
    } on Object catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> upsert(Book book) async {
    await _storage.upsertBook(book);
    state = AsyncValue.data(await _storage.loadBooks());
  }

  Future<void> touch(String bookId) async {
    await _storage.touchBook(bookId);
    state = AsyncValue.data(await _storage.loadBooks());
  }

  Future<void> delete(String bookId) async {
    await _storage.deleteBook(bookId);
    state = AsyncValue.data(await _storage.loadBooks());
  }
}

class ShelfPage extends ConsumerStatefulWidget {
  const ShelfPage({super.key});

  @override
  ConsumerState<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends ConsumerState<ShelfPage> {
  bool _openingBook = false;

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(shelfBooksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('本地听书'),
        actions: [
          IconButton(
            tooltip: '导入书籍',
            icon: const Icon(Icons.add),
            onPressed: _openingBook ? null : () => _pickAndOpen(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          books.when(
            data: (items) {
              if (items.isEmpty) {
                return _EmptyShelf(
                  onPick: _openingBook ? null : () => _pickAndOpen(context),
                );
              }
              return _BookshelfList(
                books: items.take(10).toList(growable: false),
                onOpen:
                    _openingBook ? null : (book) => _openBook(context, book),
                onDelete: _openingBook ? null : _confirmDeleteBook,
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          if (_openingBook)
            const ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAndOpen(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: const ['txt', 'epub'],
    );

    final path = result?.files.single.path;
    if (path == null) {
      return;
    }

    final parsed = await _parseWithOverlay(path);
    if (parsed == null || !context.mounted) {
      return;
    }

    final book = parsed.book.copyWith(lastOpenedAt: DateTime.now());
    await ref.read(shelfBooksProvider.notifier).upsert(book);
    if (!context.mounted) {
      return;
    }
    await _pushReader(context, parsed.copyWith(book: book));
  }

  Future<void> _openBook(BuildContext context, Book book) async {
    if (!File(book.path).existsSync()) {
      _showMessage(context, '找不到原文件，请重新导入');
      return;
    }

    await ref.read(shelfBooksProvider.notifier).touch(book.id);
    final parsed = await _parseWithOverlay(book.path);
    if (parsed == null || !context.mounted) {
      return;
    }

    await _pushReader(context, parsed.copyWith(book: book));
    await ref.read(shelfBooksProvider.notifier).load();
  }

  Future<ParsedBook?> _parseWithOverlay(String path) async {
    setState(() {
      _openingBook = true;
    });
    try {
      return await ref.read(bookParserProvider).parse(path);
    } on Object catch (error) {
      if (mounted) {
        _showMessage(context, error.toString());
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _openingBook = false;
        });
      }
    }
  }

  Future<void> _pushReader(BuildContext context, ParsedBook parsed) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReaderView(
          book: parsed.book,
          chapters: parsed.chapters,
          initialChapterIndex: parsed.book.currentChapterIndex,
          initialScrollProgress: parsed.book.progress,
          initialTtsSentenceIndex: parsed.book.ttsSentenceIndex,
        ),
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _confirmDeleteBook(Book book) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('从书架删除？'),
          content: Text('删除“${book.title}”的书架记录，不会删除原始文件。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    await ref.read(shelfBooksProvider.notifier).delete(book.id);
    if (mounted) {
      _showMessage(context, '已从书架删除');
    }
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({
    required this.onPick,
  });

  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        icon: const Icon(Icons.upload_file),
        label: const Text('导入 TXT / EPUB'),
        onPressed: onPick,
      ),
    );
  }
}

class _BookshelfList extends StatelessWidget {
  const _BookshelfList({
    required this.books,
    required this.onOpen,
    required this.onDelete,
  });

  final List<Book> books;
  final ValueChanged<Book>? onOpen;
  final ValueChanged<Book>? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: books.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final book = books[index];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          leading: CircleAvatar(
            child: Text(book.format == BookFormat.epub ? 'E' : 'T'),
          ),
          title: Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '第 ${book.currentChapterIndex + 1} 章 · ${(book.progress * 100).toStringAsFixed(1)}%',
          ),
          trailing: PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'delete' && onDelete != null) {
                onDelete!(book);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'delete',
                child: Text('从书架删除'),
              ),
            ],
          ),
          onTap: onOpen == null ? null : () => onOpen!(book),
          onLongPress: onDelete == null ? null : () => onDelete!(book),
        );
      },
    );
  }
}
