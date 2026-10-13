enum DownloadStage { notDownloaded, queued, downloading, downloaded, failed }

class DownloadStatus {
  final DownloadStage stage;
  final double progress;

  const DownloadStatus({this.stage = DownloadStage.notDownloaded, this.progress = 0});
}

enum StreamingQuality { original, high, medium, low }

extension StreamingQualityLabel on StreamingQuality {
  String get label {
    switch (this) {
      case StreamingQuality.original:
        return 'Original';
      case StreamingQuality.high:
        return 'High';
      case StreamingQuality.medium:
        return 'Medium';
      case StreamingQuality.low:
        return 'Low';
    }
  }

  String get description {
    switch (this) {
      case StreamingQuality.original:
        // The plan's wording for this option (§4.1): it promises the source
        // file, and is honest that what the device does with it is a separate
        // question — rather than implying output fidelity it can't control.
        return 'Uses the original file when available. Device output may vary.';
      case StreamingQuality.high:
        return 'Higher bandwidth use.';
      case StreamingQuality.medium:
        return 'Balances quality and data use.';
      case StreamingQuality.low:
        return 'Uses less data.';
    }
  }
}

enum PlayerRepeatMode { off, all, one }
