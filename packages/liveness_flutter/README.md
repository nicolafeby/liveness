# Liveness Flutter

Flutter client untuk layanan liveness pada repository ini. Package release
dibuat oleh GitHub Actions dan sudah berisi endpoint production, sehingga
aplikasi konsumen tidak perlu mengatur URL server.

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
