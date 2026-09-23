# Backend liveness detection

Prototipe API Python untuk tantangan kamera: wajah di tengah selama dua frame → mata terbuka → satu frame mata tertutup → mata terbuka lagi pada dua frame dalam 1,5 detik → menoleh sedikit ke kiri atau kanan pada dua frame → kembali menghadap kamera pada dua frame. Mobile memakai stream kamera agar dapat mengirim frame lebih sering selama tahap kedip. Deteksi wajah frontal, mata, dan pencahayaan tetap memakai OpenCV Haar; tahap menoleh memakai lima landmark mata dan hidung dari model YuNet OpenCV. Penyelarasan memakai posisi dan ukuran kotak wajah pada gambar kamera; koordinat ini belum dikalibrasi terhadap crop preview dan bingkai panduan mobile. Hasil `passed` sekarang juga memerlukan skor passive anti-spoofing dari sedikitnya lima frame wajah berwarna. Ini tetap prototipe; jangan gunakan hasilnya sebagai satu-satunya dasar autentikasi atau KYC.

Passive anti-spoofing memakai [MiniFASNetV2 dari Silent Face Anti-Spoofing](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing) dalam [konversi ONNX](https://huggingface.co/garciafido/minifasnet-v2-anti-spoofing-onnx) dengan SHA-256 `d7b3cd9ba8a7ceb13baa8c4720902e27ca3112eff52f926c08804af6b6eecc7b`. Inputnya crop wajah BGR 80×80 dengan margin 2,7 kali dan nilai piksel **0–255**, mengikuti praproses proyek asli. Indeks keluaran **1** adalah wajah asli sesuai kode pengujian proyek asli; indeks 0 dan 2 diperlakukan bersama sebagai serangan presentasi. Model ini ditujukan untuk foto dan tampilan layar, termasuk replay, tetapi keputusan saat ini menggabungkan skor beberapa frame dari model gambar tunggal; belum ada model gerakan temporal khusus. Sesi tidak dihentikan hanya karena lima skor awal rendah. `passed` memerlukan median skor asli minimal 0,5 pada akhir tantangan; skor yang lebih rendah menghasilkan pesan bahwa pemeriksaan belum meyakinkan, tanpa mengklaim media wajah terdeteksi. Ambang tersebut awal dan perlu kalibrasi dengan kamera, pencahayaan, foto cetak, layar HP/monitor, dan video replay nyata. Tipe serangan spesifik tidak dilaporkan karena label dua kelas serangan belum terverifikasi. Mask/3D spoof belum menjadi target validasi.

Pencahayaan diukur dari area tengah wajah pada gambar asli. Frame dengan median intensitas di bawah 55, di atas 205, atau lebih dari 45% area wajah hampir hitam/putih akan mengulang penyelarasan dan memberi instruksi memperbaiki cahaya. Ambang ini bersifat heuristik dan perlu diuji pada perangkat serta kondisi nyata; pemeriksaan ini tidak mendeteksi kacamata hitam atau menjamin ketahanan terhadap spoofing.

Deteksi mata mencoba Haar cascade mata biasa dan varian `eye_tree_eyeglasses` pada wajah yang sudah diratakan kontrasnya, lalu mencoba lagi dengan peningkatan kontras lokal jika perlu. Dua kandidat hanya diterima jika berada pada sisi kiri dan kanan wajah dengan tinggi yang berdekatan. Ini mengurangi kegagalan saat satu cascade melewatkan mata, tetapi perubahan sensitivitas masih perlu diuji dengan rekaman kamera nyata, termasuk saat mata tertutup.

Pada tahap menoleh, YuNet memperkirakan perubahan arah wajah dari posisi hidung relatif terhadap kedua mata. Satu frame awal menjadi acuan; perubahan estimasi minimal 15° pada dua frame diterima sebagai menoleh, lalu perubahan maksimal 8° pada dua frame berikutnya diterima sebagai kembali menghadap kamera. Sudut ini adalah pendekatan dari landmark dua dimensi, bukan pengukuran pose tiga dimensi. Frame abu-abu lama tetap dipakai; tahap menoleh mengubahnya menjadi gambar tiga kanal untuk input model. Jika pelacakan wajah atau pencahayaan terganggu, tahap ini dipertahankan hingga dua detik untuk memberi waktu memperbaiki posisi. Ambang perlu dikalibrasi pada perangkat dan pengguna nyata.

Model `face_detection_yunet_2023mar.onnx` berasal dari [OpenCV Zoo](https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet) dan dibundel dalam image backend.

## Menjalankan

Pull request yang mengubah `backend/` menjalankan seluruh unit test dengan Python 3.12
melalui workflow `.github/workflows/backend-pr-check.yml`.

Gunakan interpreter Python yang didukung paket dalam `requirements.txt` (teruji dengan Python 3.14 di macOS ARM).

```sh
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cd ..
./script/run-backend.sh
```

Hubungkan perangkat Android melalui USB, aktifkan USB debugging, dan pastikan `adb devices`
menampilkan perangkat dengan status `device`. Skrip memasang `adb reverse tcp:8000 tcp:8000`
sebelum menjalankan backend di loopback. Jika perangkat dilepas atau ADB terputus, jalankan ulang skrip.

Dokumentasi interaktif di komputer: `http://127.0.0.1:8000/docs`.

## API

1. `POST /sessions` membuat sesi dengan masa berlaku 120 detik.
2. `POST /sessions/{session_id}/frames` menerima multipart field `image` berupa JPEG/PNG (maksimal 5 MB). Kirim satu frame setiap minimal 80 ms sesuai `instruction` pada respons.
3. Respons berhasil memiliki format `success`, `message`, `data`, `errors`. Status tantangan (`status`, `passed`, `instruction`, `frames_processed`) berada di dalam `data`. Sesi berhenti setelah berhasil, kedaluwarsa, atau 180 frame.
4. `GET /health` untuk pemeriksaan proses.

Alternatif untuk pengiriman frame berulang adalah WebSocket `WS /sessions/{session_id}/stream`.
URL untuk Android melalui USB: `ws://127.0.0.1:8000/sessions/SESSION_ID/stream`.
Pembuatan sesi dari Android memakai `http://127.0.0.1:8000/sessions`.
Setelah `POST /sessions`, hubungkan ke URL tersebut. Server segera mengirim status sesi sebagai JSON
dengan format `success`, `message`, `data`, `errors`. Kirim **satu frame JPEG/PNG sebagai pesan biner**,
tunggu respons JSON, lalu kirim frame berikutnya dengan interval minimal 80 ms. Pesan teks atau gambar
tidak valid mendapat respons `success: false`; koneksi tetap terbuka agar mobile dapat mencoba lagi.
Sesi yang tidak ada atau kedaluwarsa ditutup dengan kode 4404, sesi yang sudah selesai dengan 4409,
dan keberhasilan atau kegagalan tantangan menutup koneksi dengan kode 1000 setelah respons terakhir.
Payload gambar maksimal 5 MB. Endpoint HTTP tetap tersedia.

Khusus WebSocket, mobile mengirim frame BGR mentah berformat `LVC1`:
4 byte ASCII `LVC1`, lebar dan tinggi masing-masing 2 byte big-endian, lalu tiga byte BGR
untuk setiap piksel (baris demi baris). Mobile merotasi frame ke posisi tegak dan mengecilkan
sisi terpanjang menjadi paling banyak 640 piksel sebelum pengiriman. Frame `LVY1` lama ditolak
karena tidak memiliki data warna untuk model. Endpoint HTTP tetap menerima JPEG/PNG saja.

```sh
curl -X POST http://127.0.0.1:8000/sessions
curl -X POST -F 'image=@frame.jpg;type=image/jpeg' http://127.0.0.1:8000/sessions/SESSION_ID/frames
```

Contoh respons berhasil (`POST /sessions`):

```json
{"success":true,"message":"Sesi berhasil dibuat","data":{"session_id":"...","expires_in_seconds":120,"status":"align","passed":false,"instruction":"Posisikan wajah di tengah bingkai","frames_processed":0},"errors":null}
```

Contoh respons gagal validasi (HTTP 422):

```json
{"success":false,"message":"Data permintaan tidak valid","data":null,"errors":[{"field":"body.image","message":"Field required"}]}
```

Sesi disimpan dalam memori proses dan gambar tidak disimpan oleh aplikasi. Deployment produksi memerlukan penyimpanan sesi bersama, pembatasan laju, autentikasi, TLS, dan model anti-spoofing yang diuji pada data relevan.

## Deploy ke home server

Push ke branch `main` yang mengubah file dalam `backend/` akan menjalankan workflow
`.github/workflows/backend-deploy.yml`. Workflow menggunakan self-hosted runner Linux
berlabel `research-liveness` yang sudah dipakai proyek ini. Runner harus berjalan di
home server, memiliki Docker dan izin untuk menjalankan perintah `docker` tanpa sudo.

Workflow membangun image dari `backend/Dockerfile`, menjalankan container
`research-liveness-backend`, lalu menunggu health check. Backend tersedia di
`http://<alamat-home-server>:18080/health`. Port host `18080` dipilih dari daftar port
Docker yang diberikan. Pastikan port itu juga tidak digunakan proses lain di host;
Docker akan menolak deployment bila port sedang dipakai. Container lama akan
dikembalikan jika container baru gagal sehat. Deployment mereset sesi yang tersimpan
di memori, sehingga sesi yang sedang berlangsung harus dimulai ulang.
