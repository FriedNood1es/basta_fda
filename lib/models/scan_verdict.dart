enum RegistrationStatus { registered, unregistered }

extension RegistrationStatusLabel on RegistrationStatus {
  String get label => switch (this) {
        RegistrationStatus.registered => 'Registered',
        RegistrationStatus.unregistered => 'Unregistered',
      };
}

enum ImageCheckStatus { recognized, unrecognized, skipped, failed, pending }

extension ImageCheckStatusLabel on ImageCheckStatus {
  String get label => switch (this) {
        ImageCheckStatus.recognized => 'Recognized',
        ImageCheckStatus.unrecognized => 'Unrecognized',
        ImageCheckStatus.skipped => 'Skipped',
        ImageCheckStatus.failed => 'Failed',
        ImageCheckStatus.pending => 'Checking...',
      };

  bool get needsWarning =>
      this == ImageCheckStatus.skipped || this == ImageCheckStatus.failed;
}

class ImageCheckResult {
  final ImageCheckStatus status;
  final Map<String, String>? info;
  const ImageCheckResult({required this.status, this.info});

  ImageCheckResult copyWith({
    ImageCheckStatus? status,
    Map<String, String>? info,
  }) {
    return ImageCheckResult(
      status: status ?? this.status,
      info: info ?? this.info,
    );
  }
}
