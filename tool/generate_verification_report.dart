import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final resultsPath = args.isNotEmpty
      ? args.first
      : 'build/verification_eval_results.json';
  final file = File(resultsPath);
  if (!file.existsSync()) {
    stderr.writeln(
      'Results file not found at $resultsPath. Run the verification eval test first.',
    );
    exitCode = 1;
    return;
  }

  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final summary = data['summary'] as Map<String, dynamic>? ?? {};
  final categories =
      (data['categories'] as Map<String, dynamic>? ?? {}).map(
    (key, value) => MapEntry(key, value as Map<String, dynamic>),
  );
  final samples =
      (data['samples'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

  final buffer = StringBuffer()
    ..writeln('# Verification Evaluation Report')
    ..writeln()
    ..writeln('Generated: ${DateTime.now().toIso8601String()}')
    ..writeln()
    ..writeln('## Overall Summary')
    ..writeln('| Metric | Value |')
    ..writeln('| --- | --- |')
    ..writeln('| Total | ${summary['total'] ?? '-'} |')
    ..writeln('| Correct | ${summary['correct'] ?? '-'} |')
    ..writeln('| Accuracy | ${summary['accuracy'] ?? '-'} |')
    ..writeln('| Precision | ${summary['precision'] ?? '-'} |')
    ..writeln('| Recall | ${summary['recall'] ?? '-'} |')
    ..writeln('| TP | ${summary['tp'] ?? '-'} |')
    ..writeln('| TN | ${summary['tn'] ?? '-'} |')
    ..writeln('| FP | ${summary['fp'] ?? '-'} |')
    ..writeln('| FN | ${summary['fn'] ?? '-'} |')
    ..writeln();

  if (categories.isNotEmpty) {
    buffer
      ..writeln('## Accuracy by Category')
      ..writeln('| Category | Total | Accuracy | Precision | Recall |')
      ..writeln('| --- | --- | --- | --- | --- |');
    categories.forEach((key, value) {
      buffer
        ..writeln(
          '| $key | ${value['total']} | ${value['accuracy']} | ${value['precision']} | ${value['recall']} |',
        );
    });
    buffer..writeln()..writeln('### Category Breakdown Chart (ASCII)');
    categories.forEach((key, value) {
      final total = (value['total'] as num?)?.toInt() ?? 0;
      final correct = (value['correct'] as num?)?.toInt() ?? 0;
      final incorrect = total - correct;
      final correctBar = '¦' * correct.clamp(0, 50);
      final incorrectBar = '¦' * incorrect.clamp(0, 50);
      buffer.writeln('$key [$correct/$total] $correctBar$incorrectBar');
    });
    buffer.writeln();
  }

  if (samples.isNotEmpty) {
    buffer
      ..writeln('## Sample Results')
      ..writeln('| Image | Expected | Predicted | Status | Category | Reg Override |')
      ..writeln('| --- | --- | --- | --- | --- | --- |');
    for (final s in samples) {
      buffer.writeln(
        '| ${s['image_path']} | ${s['expected']} | ${s['predicted']} | ${s['status']} | ${s['category']} | ${s['reg_override']} |',
      );
    }
  }

  final reportFile = File('build/verification_eval_report.md');
  reportFile
    ..createSync(recursive: true)
    ..writeAsStringSync(buffer.toString());

  stdout.writeln('Report written to ${reportFile.path}');
}
