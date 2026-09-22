# mobile

## Android CI dan Firebase App Distribution

Workflow [mobile-firebase-distribution.yml](../.github/workflows/mobile-firebase-distribution.yml) berjalan saat file di `mobile/` berubah. Pull request menjalankan CI di runner GitHub agar kode PR tidak berjalan pada server sendiri. Semua push menjalankan `flutter analyze`, `flutter test`, dan build APK debug pada self-hosted runner Linux X64 berlabel `research-liveness` (`ncladrserver`). Push ke `main` juga mengunggah APK tersebut ke Firebase App Distribution.

Runner harus tetap online dan memiliki Android SDK (termasuk build tools dan lisensi yang diperlukan), `git`, Python 3, dan Flutter **3.41.6** pada `PATH` milik proses runner. Workflow memeriksa versi Flutter yang sudah terpasang dan tidak mengunduh Flutter untuk push. Pastikan `flutter --version --machine` dapat dijalankan oleh user yang menjalankan service runner; `PATH` pada service bisa berbeda dari terminal interaktif. Pull request tetap menyiapkan Flutter pada runner GitHub yang baru. Workflow juga menyiapkan Java 17 dan Node.js 22 serta mengunduh Gradle dan dependensi bila belum ada di cache.

Siapkan distribusi satu kali:

1. Buka Firebase Console, pilih project `research-liveness`, lalu buka **App Distribution** untuk aplikasi Android `id.nicolafsalv.liveness` dan klik **Get started**.
2. Buat grup tester di App Distribution dan tambahkan alamat email tester. Catat **alias** grup, misalnya `qa-team`.
3. Di Google Cloud project yang sama, buat service account dengan role **Firebase App Distribution Admin** dan unduh JSON private key. Simpan seluruh isi JSON sebagai GitHub Actions repository secret bernama `FIREBASE_SERVICE_ACCOUNT`. Jangan commit private key ke repo.
4. Buat GitHub Actions repository variable `FIREBASE_TESTER_GROUPS` berisi alias grup tester. Beberapa alias dapat dipisahkan koma.

Workflow mengambil Firebase App ID dari `android/app/google-services.json`. APK yang dikirim adalah build **debug**, sehingga hanya ditujukan untuk pengujian. Untuk distribusi build release, siapkan signing key release terlebih dahulu lalu ubah perintah build dan lokasi APK di workflow.

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
