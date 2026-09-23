# Liveness

## Android CI dan Firebase App Distribution

Workflow [mobile-firebase-distribution.yml](../.github/workflows/mobile-firebase-distribution.yml) berjalan saat file di `mobile/` berubah. Pull request menjalankan CI di runner GitHub agar kode PR tidak berjalan pada server sendiri. Semua push menjalankan `flutter analyze`, `flutter test`, dan build APK release pada self-hosted runner Linux X64 berlabel `research-liveness` (`ncladrserver`). Push ke `main` menjalankan job distribusi terpisah yang mengunduh APK hasil build dan mengunggahnya ke Firebase App Distribution memakai environment GitHub `research`.

Runner harus tetap online dan memiliki Android SDK (termasuk build tools dan lisensi yang diperlukan), `git`, Python 3, serta FVM. Workflow mencari FVM pada `PATH`, `~/.pub-cache/bin`, `~/.local/bin`, dan path server `ncladrserver` `/home/ncladr/fvm/bin/fvm`. Jika FVM berpindah lokasi, buat GitHub Actions **repository variable** `FVM_EXECUTABLE` berisi path absolut ke file `fvm`; variable pada environment `research` tidak tersedia bagi job `ci`. Versi Flutter **3.41.6** dipatok di `.fvmrc`. Pada push, workflow menjalankan `fvm use 3.41.6 --skip-pub-get` dan memakai SDK yang dipilih FVM untuk semua step Flutter. FVM menggunakan cache SDK yang sudah ada dan hanya mengunduh jika versi tersebut belum terpasang. Variable `FLUTTER_SDK_PATH` tidak diperlukan. Pull request tetap menyiapkan Flutter pada runner GitHub yang baru. Workflow juga menyiapkan Java 17 dan Node.js 22 serta mengunduh Gradle dan dependensi bila belum ada di cache.

Untuk distribusi, pasang Firebase CLI sekali pada self-hosted runner dengan `npm install --global firebase-tools@15.30.1` dan pastikan perintah `firebase` tersedia pada `PATH` akun yang menjalankan GitHub Actions runner. Job CD memeriksa `firebase --version` dan berhenti jika versinya bukan `15.30.1`; workflow tidak memasang ulang CLI pada setiap run. Jika versi CLI diperbarui, ubah versi pada runner dan langkah pemeriksaan workflow secara bersamaan.

Siapkan distribusi satu kali:

1. Buka Firebase Console, pilih project `research-liveness`, lalu buka **App Distribution** untuk aplikasi Android `id.nicolafsalv.liveness` dan klik **Get started**.
2. Buat grup tester di App Distribution dan tambahkan alamat email tester. Catat **alias** grup, misalnya `qa-team`.
3. Di Google Cloud project yang sama, buat service account dengan role **Firebase App Distribution Admin** dan unduh JSON private key. Simpan seluruh isi JSON sebagai GitHub Actions **environment secret** bernama `FIREBASE_SERVICE_ACCOUNT` pada environment `research`. Jangan commit private key ke repo.
4. Buat GitHub Actions **environment variable** `FIREBASE_TESTER_GROUPS` pada environment `research` berisi alias grup tester. Beberapa alias dapat dipisahkan koma.

Workflow mengambil Firebase App ID dari `android/app/google-services.json`. APK yang dikirim adalah build **release** untuk pengujian. Build number Android (`versionCode`) otomatis memakai nomor run GitHub Actions, sedangkan versi aplikasi (`versionName`) tetap mengikuti `pubspec.yaml`. Release notes di Firebase berisi pesan dari lima commit terbaru. Pastikan konfigurasi signing Android sesuai kebutuhan sebelum mendistribusikannya lebih luas.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Backend liveness

Model respons API memakai `json_serializable`. Setelah mengubah field atau anotasi di
`packages/liveness_flutter/lib/src/liveness/models/`, jalankan
`flutter pub run build_runner build --delete-conflicting-outputs` dari direktori
`packages/liveness_flutter/` dan commit file `.g.dart` yang dihasilkan.

Jalankan `./script/run-backend.sh` dari root proyek, lalu jalankan aplikasi pada perangkat Android yang terhubung melalui USB. Skrip mengaktifkan `adb reverse tcp:8000 tcp:8000`; aplikasi memakai `http://127.0.0.1:8000` secara default. Aplikasi membuat sesi, membuka WebSocket lalu mengirim foto JPEG kamera depan satu per satu setelah menerima respons server, dan menampilkan instruksi serta hasil dari backend. Ketuk **Coba lagi** untuk membuat sesi baru setelah gagal.

Untuk perangkat lain, atur URL backend saat menjalankan Flutter, misalnya `flutter run --dart-define=LIVENESS_API_URL=http://192.168.1.10:8000`. Backend harus dapat diakses dari perangkat; untuk akses LAN jalankan uvicorn dengan `--host 0.0.0.0`. Gunakan HTTPS dan konfigurasi keamanan platform yang sesuai di luar lingkungan pengembangan lokal.

Untuk APK yang didistribusikan lewat GitHub Actions, atur variable `LIVENESS_API_URL` pada GitHub environment `research` ke URL backend yang dapat diakses perangkat penguji. Workflow meneruskannya ke `flutter build` melalui `--dart-define`. Build rilis gagal jika variable tersebut belum diatur.

## Menggunakan sebagai package

Entry point publik package adalah
`package:liveness_flutter/liveness_flutter.dart`. Source package berada di
`packages/liveness_flutter`. Konsumen dapat memasang package langsung sebagai
Git dependency:

```yaml
dependencies:
  liveness_flutter:
    git:
      url: https://github.com/USERNAME/research-liveness.git
      ref: liveness-v1.0.1
      path: packages/liveness_flutter
```

Pemakaian paling sederhana tidak memerlukan URL:

```dart
import 'package:liveness_flutter/liveness_flutter.dart';

LivenessScreen(
  onSuccess: (image) {
    // Gunakan foto hasil liveness.
  },
)
```

Android host wajib memiliki permission `CAMERA` dan `INTERNET`; iOS host wajib
memiliki `NSCameraUsageDescription`. Parameter `baseUrl` tetap tersedia sebagai
override untuk development dan pengujian.
