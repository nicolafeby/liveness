# mobile

## Android CI dan Firebase App Distribution

Workflow [mobile-firebase-distribution.yml](../.github/workflows/mobile-firebase-distribution.yml) berjalan saat file di `mobile/` berubah. Pull request menjalankan CI di runner GitHub agar kode PR tidak berjalan pada server sendiri. Semua push menjalankan `flutter analyze`, `flutter test`, dan build APK release pada self-hosted runner Linux X64 berlabel `research-liveness` (`ncladrserver`). Push ke `main` menjalankan job distribusi terpisah yang mengunduh APK hasil build dan mengunggahnya ke Firebase App Distribution memakai environment GitHub `research`.

Runner harus tetap online dan memiliki Android SDK (termasuk build tools dan lisensi yang diperlukan), `git`, Python 3, serta FVM. Workflow mencari FVM pada `PATH`, `~/.pub-cache/bin`, dan `~/.local/bin` milik user service runner. Jika FVM terpasang di lokasi lain, buat GitHub Actions **repository variable** `FVM_EXECUTABLE` berisi path absolut ke file `fvm`; cari path tersebut di server dengan `command -v fvm`. Versi Flutter **3.41.6** dipatok di `.fvmrc`. Pada push, workflow menjalankan `fvm use 3.41.6 --skip-pub-get` dan memakai SDK yang dipilih FVM untuk semua step Flutter. FVM menggunakan cache SDK yang sudah ada dan hanya mengunduh jika versi tersebut belum terpasang. Variable `FLUTTER_SDK_PATH` tidak diperlukan. Pull request tetap menyiapkan Flutter pada runner GitHub yang baru. Workflow juga menyiapkan Java 17 dan Node.js 22 serta mengunduh Gradle dan dependensi bila belum ada di cache.

Siapkan distribusi satu kali:

1. Buka Firebase Console, pilih project `research-liveness`, lalu buka **App Distribution** untuk aplikasi Android `id.nicolafsalv.liveness` dan klik **Get started**.
2. Buat grup tester di App Distribution dan tambahkan alamat email tester. Catat **alias** grup, misalnya `qa-team`.
3. Di Google Cloud project yang sama, buat service account dengan role **Firebase App Distribution Admin** dan unduh JSON private key. Simpan seluruh isi JSON sebagai GitHub Actions **environment secret** bernama `FIREBASE_SERVICE_ACCOUNT` pada environment `research`. Jangan commit private key ke repo.
4. Buat GitHub Actions **environment variable** `FIREBASE_TESTER_GROUPS` pada environment `research` berisi alias grup tester. Beberapa alias dapat dipisahkan koma.

Workflow mengambil Firebase App ID dari `android/app/google-services.json`. APK yang dikirim adalah build **release** untuk pengujian. Pastikan konfigurasi signing Android sesuai kebutuhan sebelum mendistribusikannya lebih luas.

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
