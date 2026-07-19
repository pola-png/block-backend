class HomeFeedBatchLayout {
  const HomeFeedBatchLayout._();

  static int completedBatchCount(int postCount) => postCount ~/ 5;

  static int batchAdRowCount(int postCount, {required bool enableFeedAds}) {
    return enableFeedAds ? completedBatchCount(postCount) * 3 : 0;
  }

  static int batchItemCount(
    int postCount, {
    required bool enableFeedAds,
    required bool includeLoading,
  }) {
    return postCount +
        batchAdRowCount(postCount, enableFeedAds: enableFeedAds) +
        (includeLoading ? 1 : 0);
  }

  static bool canShowBatchAds(int postCount, {required bool enableFeedAds}) {
    return enableFeedAds && postCount >= 5;
  }

  static bool isBatchAdRow(int rowIndex, int postCount) {
    final fullRowCount = completedBatchCount(postCount) * 8;
    if (rowIndex >= fullRowCount) return false;
    final positionInBatch = rowIndex % 8;
    return positionInBatch == 1 || positionInBatch == 4 || positionInBatch == 7;
  }

  static int batchAdSlotForRow(int rowIndex) {
    final batchIndex = rowIndex ~/ 8;
    switch (rowIndex % 8) {
      case 1:
        return batchIndex * 3;
      case 4:
        return batchIndex * 3 + 1;
      case 7:
        return batchIndex * 3 + 2;
      default:
        return batchIndex * 3;
    }
  }

  static int batchPostIndexForRow(int rowIndex, int postCount) {
    final fullBatchCount = completedBatchCount(postCount);
    final fullRowCount = fullBatchCount * 8;
    if (rowIndex >= fullRowCount) {
      return fullBatchCount * 5 + (rowIndex - fullRowCount);
    }
    final batchIndex = rowIndex ~/ 8;
    switch (rowIndex % 8) {
      case 0:
        return batchIndex * 5;
      case 2:
        return batchIndex * 5 + 1;
      case 3:
        return batchIndex * 5 + 2;
      case 5:
        return batchIndex * 5 + 3;
      case 6:
        return batchIndex * 5 + 4;
      default:
        return batchIndex * 5;
    }
  }
}
