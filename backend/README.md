# Backend liveness detection

Prototipe API Python untuk tantangan kamera: mata terbuka → kedip (minimal dua frame) → mata terbuka → geser kepala dalam bingkai. Deteksi memakai Haar cascade OpenCV. Hasil `passed` hanya berarti urutan tantangan teramati. Video replay atau foto yang digerakkan dapat mengelabui pendekatan ini; jangan gunakan hasilnya sebagai satu-satunya dasar autentikasi atau KYC.

## Menjalankan

Disarankan Python 3.11–3.13.

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
3. Respons berisi `status`, `passed`, `instruction`, dan `frames_processed`. Sesi berhenti setelah berhasil, kedaluwarsa, atau 60 frame.
4. `GET /health` untuk pemeriksaan proses.

```sh
curl -X POST http://127.0.0.1:8000/sessions
curl -X POST -F 'image=@frame.jpg;type=image/jpeg' http://127.0.0.1:8000/sessions/SESSION_ID/frames
```

Sesi disimpan dalam memori proses dan gambar tidak disimpan oleh aplikasi. Deployment produksi memerlukan penyimpanan sesi bersama, pembatasan laju, autentikasi, TLS, dan model anti-spoofing yang diuji pada data relevan.
