import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/transfer_task.dart';

class TransferNotifier extends StateNotifier<List<TransferTask>> {
  TransferNotifier() : super([]);

  void addOrUpdate(TransferTask task) {
    final idx = state.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      state = [...state]..[idx] = task;
    } else {
      state = [task, ...state];
    }
  }

  void remove(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  void clear() {
    state = [];
  }
}

final transferProvider =
    StateNotifierProvider<TransferNotifier, List<TransferTask>>((ref) {
  return TransferNotifier();
});
