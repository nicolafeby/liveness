# Liveness Flutter

Flutter client untuk layanan liveness pada repository ini. Aplikasi konsumen
dapat langsung menggunakan package tanpa mengatur URL server.

```dart
import 'package:liveness_flutter/liveness_flutter.dart';

LivenessScreen(
  onSuccess: (image) {
    // Gunakan foto hasil liveness.
  },
)
```

Android host wajib memiliki permission `CAMERA` dan `INTERNET`. iOS host wajib
memiliki `NSCameraUsageDescription`. `baseUrl` dapat diberikan untuk development
atau pengujian.

Package dapat dipasang langsung dari GitHub:

```yaml
dependencies:
  liveness_flutter:
    git:
      url: https://github.com/nicolafeby/research-liveness.git
      ref: liveness-v1.0.1
      path: packages/liveness_flutter
```

## Pengujian

Pull request yang mengubah package menjalankan `flutter analyze` dan `flutter test`
secara otomatis. Pemeriksaan yang sama dapat dijalankan secara lokal dari direktori
package.
