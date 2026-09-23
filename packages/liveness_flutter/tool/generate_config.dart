import 'dart:io';

void main() {
  final apiUrl = Platform.environment['LIVENESS_API_URL']?.trim();
  if (apiUrl == null || apiUrl.isEmpty) {
    stderr.writeln('LIVENESS_API_URL is required');
    exitCode = 1;
    return;
  }

  final uri = Uri.tryParse(apiUrl);
  if (uri == null ||
      !uri.hasScheme ||
      !uri.hasAuthority ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    stderr.writeln('LIVENESS_API_URL must be an absolute HTTP(S) URL');
    exitCode = 1;
    return;
  }

  final escaped = apiUrl.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
  File('lib/src/core/liveness_config.g.dart').writeAsStringSync(
    '// GENERATED FILE - DO NOT EDIT.\n'
    "const generatedLivenessApiUrl = '$escaped';\n",
  );
}
