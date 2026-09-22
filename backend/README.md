# Backend liveness detection

Prototipe API Python untuk tantangan kamera: mata terbuka → kedip (minimal dua frame) → mata terbuka → geser kepala dalam bingkai. Deteksi memakai Haar cascade OpenCV. Hasil `passed` hanya berarti urutan tantangan teramati. Video replay atau foto yang digerakkan dapat mengelabui pendekatan ini; jangan gunakan hasilnya sebagai satu-satunya dasar autentikasi atau KYC.

## Menjalankan

Gunakan interpreter Python yang didukung paket dalam `requirements.txt` (teruji dengan Python 3.14 di macOS ARM).

```sh
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload
```

Dokumentasi interaktif: `http://127.0.0.1:8000/docs`.

## API

1. `POST /sessions` membuat sesi dengan masa berlaku 120 detik.
2. `POST /sessions/{session_id}/frames` menerima multipart field `image` berupa JPEG/PNG (maksimal 5 MB). Kirim satu frame setiap minimal 80 ms sesuai `instruction` pada respons.
3. Respons berhasil memiliki format `success`, `message`, `data`, `errors`. Status tantangan (`status`, `passed`, `instruction`, `frames_processed`) berada di dalam `data`. Sesi berhenti setelah berhasil, kedaluwarsa, atau 60 frame.
4. `GET /health` untuk pemeriksaan proses.

```sh
curl -X POST http://127.0.0.1:8000/sessions
curl -X POST -F 'image=@frame.jpg;type=image/jpeg' http://127.0.0.1:8000/sessions/SESSION_ID/frames
```

Contoh respons berhasil (`POST /sessions`):

```json
{"success":true,"message":"Sesi berhasil dibuat","data":{"session_id":"...","expires_in_seconds":120,"status":"open","passed":false,"instruction":"Hadap kamera dengan kedua mata terbuka","frames_processed":0},"errors":null}
```

Contoh respons gagal validasi (HTTP 422):

```json
{"success":false,"message":"Data permintaan tidak valid","data":null,"errors":[{"field":"body.image","message":"Field required"}]}
```

Sesi disimpan dalam memori proses dan gambar tidak disimpan oleh aplikasi. Deployment produksi memerlukan penyimpanan sesi bersama, pembatasan laju, autentikasi, TLS, dan model anti-spoofing yang diuji pada data relevan.
