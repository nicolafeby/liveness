# Research Liveness Detection

Prototipe end-to-end untuk memverifikasi bahwa wajah di depan kamera berasal dari pengguna yang aktif, bukan sekadar gambar statis. Proyek ini menggabungkan aplikasi Flutter sebagai pengambil frame kamera dan API FastAPI/OpenCV sebagai pemroses tantangan liveness.

> [!WARNING]
> Proyek ini masih berupa riset/prototipe. Ambang deteksi belum dikalibrasi pada populasi, perangkat, dan kondisi serangan yang representatif. Jangan gunakan hasilnya sebagai satu-satunya dasar autentikasi, KYC, atau keputusan berisiko tinggi.

## Fitur utama

- Panduan kamera real-time untuk posisi, jarak, jumlah wajah, dan pencahayaan.
- Active liveness berurutan: wajah sejajar, mata terbuka, berkedip, menoleh, lalu kembali menghadap kamera.
- Passive anti-spoofing pada beberapa frame menggunakan MiniFASNetV2 ONNX.
- Deteksi wajah dan mata dengan OpenCV Haar Cascade serta estimasi arah wajah dari landmark YuNet.
- Komunikasi mobile–backend melalui HTTP untuk membuat sesi dan WebSocket untuk mengirim frame.
- Frame diproses di memori dan tidak disimpan oleh backend.
- Pengujian unit untuk state machine, detektor, protokol stream, konversi frame, dan klien API.
- Docker deployment backend dan distribusi APK Android melalui Firebase App Distribution.

## Arsitektur

```text
Kamera depan Flutter
       │
       │ frame BGR LVC1 (WebSocket)
       ▼
FastAPI ──► OpenCV Haar / YuNet ──► observasi wajah, mata, cahaya, arah
       │
       ├──► MiniFASNetV2 ─────────► skor passive anti-spoofing
       │
       └──► state machine ────────► instruksi / passed / failed
                    │
                    └─────────────► UI Flutter
```

Alur verifikasi yang diterapkan:

1. Wajah tunggal harus berada di tengah dengan ukuran yang sesuai selama dua frame.
2. Kedua mata harus terlihat, kemudian pengguna diminta berkedip.
3. Mata harus kembali terbuka pada dua frame dalam waktu maksimal 1,5 detik.
4. Pengguna menoleh sedikit ke kiri atau kanan pada dua frame, lalu kembali menghadap kamera pada dua frame.
5. Tantangan hanya dinyatakan berhasil jika tersedia sedikitnya lima sampel passive anti-spoofing dan median skor wajah asli mencapai ambang `0.5`.

Sesi berlaku selama 120 detik, dibatasi 180 frame, dan menerima frame dengan interval minimal 80 ms. Aplikasi mobile mengirim lebih sering saat tahap kedip (sekitar 100 ms) dan sekitar 300 ms pada tahap lain.

## Struktur repositori

```text
.
├── backend/                 # FastAPI, state machine, OpenCV, dan model ONNX
│   ├── main.py              # Endpoint HTTP dan WebSocket
│   ├── challenge.py         # Aturan serta status tantangan
│   ├── detector.py          # Deteksi wajah, mata, cahaya, yaw, anti-spoofing
│   ├── *_test.py            # Pengujian backend
│   ├── Dockerfile
│   └── README.md            # Detail algoritma, API, dan deployment backend
├── mobile/                  # Aplikasi Flutter
│   ├── lib/core/            # API client dan encoding frame kamera
│   ├── lib/liveness/        # BLoC, model, dan layar liveness
│   ├── test/                # Pengujian Flutter
│   └── README.md            # Detail CI dan Firebase App Distribution
├── script/run-backend.sh    # Backend lokal + adb reverse
└── .github/workflows/       # Deployment backend dan pipeline mobile
```

## Prasyarat

- Python yang kompatibel dengan `backend/requirements.txt` (image Docker memakai Python 3.12).
- Flutter 3.41.6 dan Dart yang sesuai; versi Flutter dipatok melalui FVM di `mobile/.fvmrc`.
- Android SDK dan perangkat Android dengan USB debugging untuk alur lokal yang paling sederhana.
- `adb` tersedia pada `PATH`.

Struktur iOS tersedia dan izin kamera sudah dikonfigurasi, tetapi otomatisasi build/distribusi dalam repositori saat ini berfokus pada Android.

## Menjalankan secara lokal

### 1. Siapkan backend

```sh
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cd ..
```

Hubungkan perangkat Android, aktifkan USB debugging, lalu pastikan perangkat terdeteksi:

```sh
adb devices
```

Jalankan backend dari root repositori:

```sh
./script/run-backend.sh
```

Skrip tersebut memasang `adb reverse tcp:8000 tcp:8000` dan menjalankan Uvicorn pada `127.0.0.1:8000` dengan hot reload. Dokumentasi OpenAPI tersedia di <http://127.0.0.1:8000/docs>.

Backend juga dapat dijalankan tanpa perangkat Android:

```sh
cd backend
.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### 2. Jalankan aplikasi Flutter

Di terminal lain:

```sh
cd mobile
fvm flutter pub get
fvm flutter run
```

URL default aplikasi adalah `http://127.0.0.1:8000`, sehingga dapat langsung digunakan bersama `adb reverse`. Untuk perangkat di jaringan yang sama, arahkan aplikasi ke alamat backend yang dapat diakses perangkat:

```sh
fvm flutter run \
  --dart-define=LIVENESS_API_URL=http://192.168.1.10:8000
```

Untuk penggunaan di luar pengembangan lokal, gunakan HTTPS/WSS dan konfigurasi keamanan platform yang sesuai. Android saat ini mengizinkan cleartext traffic untuk kebutuhan pengembangan.

## API dan protokol frame

| Method | Endpoint | Kegunaan |
| --- | --- | --- |
| `GET` | `/health` | Health check proses backend |
| `POST` | `/sessions` | Membuat sesi liveness baru |
| `POST` | `/sessions/{session_id}/frames` | Mengirim satu JPEG/PNG melalui multipart field `image` |
| `WS` | `/sessions/{session_id}/stream` | Bertukar frame biner dan hasil secara berurutan |

Contoh penggunaan HTTP:

```sh
curl -X POST http://127.0.0.1:8000/sessions
curl -X POST \
  -F 'image=@frame.jpg;type=image/jpeg' \
  http://127.0.0.1:8000/sessions/SESSION_ID/frames
```

Aplikasi mobile menggunakan format biner internal `LVC1` melalui WebSocket:

```text
4 byte  : ASCII "LVC1"
2 byte  : lebar, unsigned big-endian
2 byte  : tinggi, unsigned big-endian
N byte  : piksel BGR, tiga byte per piksel
```

Frame kamera dirotasi ke posisi tegak dan diperkecil hingga sisi terpanjang maksimal 640 piksel sebelum dikirim. WebSocket mengharuskan pola satu frame lalu satu respons; ukuran payload maksimal 5 MB. Endpoint HTTP hanya menerima JPEG/PNG.

Respons API memakai envelope berikut:

```json
{
  "success": true,
  "message": "Frame berhasil diproses",
  "data": {
    "status": "blink",
    "passed": false,
    "instruction": "Kedipkan kedua mata sekali.",
    "frames_processed": 4
  },
  "errors": null
}
```

Status tantangan adalah `align`, `open`, `blink`, `reopen`, `move`, `passed`, atau `failed`.

## Pengujian

Backend memakai `unittest`:

```sh
cd backend
.venv/bin/python -m unittest discover -p 'test_*.py'
```

Mobile memakai Flutter Test:

```sh
cd mobile
fvm flutter test
```

Pemeriksaan statis dapat dijalankan dengan:

```sh
cd mobile
fvm flutter analyze
```

Setelah mengubah model beranotasi di `packages/liveness_flutter/lib/src/liveness/models/`, regenerasi serializer:

```sh
cd packages/liveness_flutter
fvm flutter pub run build_runner build --delete-conflicting-outputs
```

## Docker dan deployment

Menjalankan backend dengan Docker:

```sh
docker build -t research-liveness-backend backend
docker run --rm -p 8000:8000 research-liveness-backend
```

Push ke branch `main` yang mengubah `backend/**` menjalankan deployment pada self-hosted runner berlabel `research-liveness`. Workflow membangun container, menerbitkan backend pada port host `18080`, melakukan health check, dan mengembalikan container sebelumnya jika deployment baru gagal.

Perubahan pada `mobile/**` menjalankan tes Flutter. Push ke `main` atau eksekusi manual kemudian membangun APK release dan mendistribusikannya melalui Firebase App Distribution. Konfigurasi environment GitHub yang diperlukan:

| Nama | Jenis | Kegunaan |
| --- | --- | --- |
| `LIVENESS_API_URL` | Variable | URL backend untuk APK release |
| `FIREBASE_TESTER_GROUPS` | Variable | Alias grup tester Firebase |
| `FIREBASE_SERVICE_ACCOUNT` | Secret | JSON service account Firebase |
| `FVM_EXECUTABLE` | Variable opsional | Path absolut FVM pada self-hosted runner |

Detail penyiapan runner dan Firebase tersedia di [mobile/README.md](mobile/README.md), sedangkan detail model, ambang deteksi, API, dan deployment backend tersedia di [backend/README.md](backend/README.md).

## Batasan dan keamanan

- MiniFASNetV2 dipakai sebagai model gambar tunggal; belum ada model anti-replay temporal khusus.
- Ambang cahaya, pose, alignment, dan anti-spoofing bersifat heuristik dan perlu kalibrasi dengan data nyata.
- Target evaluasi saat ini terutama foto cetak dan tampilan layar; mask/serangan 3D belum tervalidasi.
- Sesi disimpan dalam memori satu proses dan akan hilang saat backend restart/deploy.
- Backend belum menyediakan autentikasi, rate limiting, penyimpanan sesi bersama, atau TLS.
- Aplikasi tidak menyimpan frame pada backend, tetapi data biometrik tetap dikirim melalui jaringan selama sesi. Gunakan koneksi terenkripsi dan kebijakan privasi yang sesuai pada lingkungan nyata.

## Lisensi dan model pihak ketiga

Kode proyek dilisensikan dengan [MIT License](LICENSE).

Repositori juga membundel model pihak ketiga:

- `face_detection_yunet_2023mar.onnx` dari [OpenCV Zoo](https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet).
- `minifasnet_v2.onnx`, konversi ONNX MiniFASNetV2 dari [Silent Face Anti-Spoofing](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing), dengan sumber konversi yang dijelaskan di [backend/README.md](backend/README.md).

Tinjau lisensi dan ketentuan masing-masing model sebelum distribusi atau penggunaan komersial.
