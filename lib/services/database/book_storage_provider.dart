import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'book_storage_service.dart';

final bookStorageProvider = Provider<BookStorageService>((ref) {
  return BookStorageService();
});
