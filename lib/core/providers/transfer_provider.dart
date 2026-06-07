import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TransferTask {
  final String id;
  final String name;
  final String deviceId;
  final bool isApk;
  final String? error;
  final bool isDone;
  final bool isSuccess;

  TransferTask({
    required this.id,
    required this.name,
    required this.deviceId,
    required this.isApk,
    this.error,
    this.isDone = false,
    this.isSuccess = false,
  });

  TransferTask copyWith({String? error, bool? isDone, bool? isSuccess}) {
    return TransferTask(
      id: id,
      name: name,
      deviceId: deviceId,
      isApk: isApk,
      error: error ?? this.error,
      isDone: isDone ?? this.isDone,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }
}

class TransferListNotifier extends Notifier<List<TransferTask>> {
  @override
  List<TransferTask> build() {
    return [];
  }

  void addTask(TransferTask task) {
    state = [...state, task];
  }

  void updateTask({
    required String id,
    String? error,
    bool? isDone,
    bool? isSuccess,
  }) {
    state = state.map((task) {
      if (task.id == id) {
        return task.copyWith(
          error: error,
          isDone: isDone,
          isSuccess: isSuccess,
        );
      }
      return task;
    }).toList();

    // Auto-remove completed tasks after 3 seconds
    if (isDone == true) {
      Future.delayed(const Duration(seconds: 3), () {
        removeTask(id);
      });
    }
  }

  void removeTask(String id) {
    state = state.where((task) => task.id != id).toList();
  }

  void clearCompleted() {
    state = state.where((task) => !task.isDone).toList();
  }
}

final transferListProvider =
    NotifierProvider<TransferListNotifier, List<TransferTask>>(
      TransferListNotifier.new,
    );
