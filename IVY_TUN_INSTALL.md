# Ivy TUN v2.3.1 - Hướng dẫn cài đặt

> **Chỉ dùng với thiết bị và tài khoản Roblox của chính bạn.**
> Cookie `.ROBLOSECURITY` là chìa khóa đăng nhập. Không gửi `profiles.conf`, `cookie.txt`, file export hoặc ảnh chụp màn hình có cookie cho bất kỳ ai.

## 1. Bản remake này có gì khác?

Bản gốc trong file bạn gửi đã được viết lại và tối ưu:

- **Bỏ đoạn tự tải code từ Internet rồi chạy bằng root.** Bản mới chỉ tự gọi `su` với chính file script đang chạy.
- Kiểm tra dependency (`sqlite3`, `curl`, `am`, `pm`, `pidof`, `logcat`) trước khi chạy.
- Không còn `logcat -c` toàn cục. Mỗi vòng lặp đọc **một snapshot logcat** rồi lọc theo **PID của từng app**, tránh xoá log của app khác và giảm số lần gọi `logcat`.
- Bỏ kiểm tra focus toàn cục kiểu “hễ đang ở launcher là tất cả app mất kết nối”. Trạng thái được xác định theo PID + log của chính app đó.
- Có **cooldown** sau rejoin để tránh vòng lặp rejoin liên tục.
- **Uptime webhook thực sự chạy nền** trong lúc auto-rejoin (bản gốc chỉ lưu `INTERVAL` mà không gửi).
- Webhook có kiểm tra URL Discord, escape JSON đúng cách, gửi ảnh nếu `screencap` hoạt động.
- Cookie được escape trước khi ghi SQLite; tự đọc schema bảng `cookies` để chèn đúng cột.
- Profile mới dùng **TAB**; vẫn đọc được profile cũ dùng `|` (cookie có chứa `|` vẫn được giữ nguyên).
- Không in full cookie ra màn hình; chỉ hiện dạng `abcd...wxyz`.
- Có file log `ivy-tun.log` (không ghi cookie).
- Có thể đổi thư mục cấu hình bằng biến `IVY_TUN_DIR`.
- Mục **2** và **11** quét **tất cả app đã cài** (kể cả app ở user khác hoặc app clone), không chỉ riêng app Roblox. App Roblox-like được xếp lên trước.
- Mục **2** cho phép chọn **nhiều package cùng lúc**: nhập số cách nhau bằng dấu cách, bấm `0` để xác nhận. Sau đó phải nhập **Place ID/Link riêng cho từng package**.
- Auto-rejoin tự bật `termux-wake-lock` (nếu có) để Termux không bị ngủ khi chuyển sang Roblox.
- Nhận diện disconnect theo **tất cả PID** của package, đọc log riêng của từng PID thay vì chỉ đọc log toàn hệ thống, và mở rộng mẫu log (Leave, Disconnected, Connection lost, Game left, v.v.).

## 2. Yêu cầu

- Android đã **root** (Magisk, KernelSU hoặc APatch).
- **Termux** cài từ F-Droid hoặc GitHub Termux, không dùng bản Play Store cũ.
- Đã cài ít nhất một app Roblox hoặc app clone (Delta, Fluxus, Hydrogen, Codex, v.v.).
- Mỗi app phải được **mở ít nhất một lần** để Android tạo thư mục `/data/data/<package>/app_webview`.
- Có kết nối mạng để verify cookie và gửi Discord webhook (nếu dùng).

## 3. Cài Termux và các gói cần thiết

Mở Termux, chạy:

```bash
pkg update -y
pkg install -y bash coreutils curl sqlite ncurses-utils
termux-setup-storage
```

Khi `termux-setup-storage` hỏi quyền, bấm **Allow**.

Kiểm tra:

```bash
command -v sqlite3
command -v curl
sqlite3 --version
```

Nếu `sqlite3` không có:

```bash
pkg install -y sqlite
```

## 4. Copy script sang điện thoại

Có 3 cách:

### Cách A — Tải file trực tiếp

Copy file `ivy-tun.sh` vào:

```text
/sdcard/Download/ivy-tun.sh
```

### Cách B — Dùng ADB từ máy tính

Bật USB debugging, cắm cáp, rồi chạy trên máy tính:

```bash
adb push ivy-tun.sh /sdcard/Download/
```

### Cách C — Tạo file bằng Termux

Nếu bạn dán nội dung script vào Termux:

```bash
nano /sdcard/Download/ivy-tun.sh
```

Dán toàn bộ nội dung, lưu lại. Sau đó kiểm tra cú pháp:

```bash
bash -n /sdcard/Download/ivy-tun.sh
```

Không có thông báo gì là cú pháp hợp lệ.

## 5. Cấp quyền root và chạy lần đầu

Chạy từ Termux:

```bash
bash /sdcard/Download/ivy-tun.sh
```

Script sẽ tự gọi `su`. Khi Magisk/KernelSU hỏi, chọn **Grant** cho Termux.

Nếu muốn gọi root trực tiếp:

```bash
su -c "bash /sdcard/Download/ivy-tun.sh"
```

Nếu báo `su: not found` hoặc `Permission denied`:

- Kiểm tra máy đã root thật chưa.
- Mở Magisk/KernelSU, cấp quyền root cho Termux.
- Một số ROM dùng `su` ở đường dẫn khác; thử `su -c id` để kiểm tra.

## 6. Cấu hình lần đầu

Màn hình chính có các mục:

```text
1  Start auto rejoin + uptime
2  Select apps & assign link
3  List selected packages
4  Auto-select all with one link
5  Open all Roblox tabs
6  Login via cookie (verify API)
7  Quản lý acc theo profile
8  Logout Roblox
9  Export cookies
10 Cấu hình Discord webhook/uptime
11 Xem tất cả package đã cài
12 Thoát
```

### Bước 6.1 — Chọn một hoặc nhiều app và link server

Chọn **2**:

1. Script in danh sách **tất cả app đã cài**; app Roblox-like xếp trước.
2. Nhập một hoặc nhiều số thứ tự, cách nhau bằng dấu cách. Có thể nhập từng dòng.
3. Bấm `0` để xác nhận danh sách package đã chọn.
4. Script lần lượt hỏi **Place ID/Link riêng cho từng package**. Nhập `0` để bỏ qua package đó.

Ví dụ chọn 2 package:

```text
Package (0=xác nhận): 1 2 0
Place ID/Link cho com.roblox.client (0=bỏ qua): 1234567890
Place ID/Link cho com.moons.lite (0=bỏ qua): 9876543210
```

Ví dụ link hợp lệ:

```text
1234567890
https://www.roblox.com/games/1234567890/Ten-Game
roblox://placeId=1234567890
roblox://placeId=1234567890&linkCode=ABCDEF
```

Script lưu các package đã chọn rồi quay lại menu chính.

Mục **4** là tùy chọn gán nhanh: chỉ nên dùng khi tất cả app Roblox-like thực sự vào cùng một game. **Lưu ý: mục 4 sẽ ghi đè toàn bộ `packages.conf` cũ.**

Kiểm tra bằng mục **3**.

### Bước 6.2 — Đăng nhập bằng cookie (chỉ acc của bạn)

Chọn **6**:

- **1** — đọc từng dòng trong `/sdcard/Download/cookie.txt`, gán lần lượt theo thứ tự package.
- **2** — chọn một package rồi dán cookie.

`cookie.txt` chỉ nên có **mỗi dòng một cookie**, không thêm comment hay tiêu đề. Thứ tự dòng tương ứng với thứ tự package mà script in ra.

Cookie cần dán là toàn bộ giá trị `.ROBLOSECURITY`, thường bắt đầu bằng:

```text
_|WARNING:-DO-NOT-SHARE-THIS...
```

Script sẽ gọi Roblox API để kiểm tra. Nếu hợp lệ, cookie được ghi vào WebView DB của app.

**Quan trọng:** một số bản WebView lưu cookie trong cột `encrypted_value` (mã hoá bằng key của app). Script chỉ ghi được cột `value`. Nếu đã ghi mà app vẫn chưa đăng nhập:

- Mở app, đăng nhập thủ công một lần.
- Hoặc dùng app clone có WebView lưu cookie dạng plaintext.
- Không có cách giải mã `encrypted_value` nếu không có key của app.

### Bước 6.3 — Quản lý profile

Chọn **7**:

- **1** — thêm profile: chọn package, dán cookie, verify, nhập Place ID/link.
- **2** — đồng bộ tất cả profile sang `packages.conf`.
- **3** — nạp cookie từ tất cả profile vào các app.
- **4** — xoá một profile.
- **5** — xoá toàn bộ profile.

File profile mới dùng TAB. Profile cũ dùng `|` vẫn đọc được.

### Bước 6.4 — Discord webhook và uptime

Chọn **10**:

1. Chọn **1**, dán Discord Webhook URL.
2. Chọn **2**, đặt chu kỳ uptime (phút, 1–1440).
3. Chọn **3** để gửi thử ảnh + thông báo.
4. Chọn **0** để quay lại.

Cách tạo webhook:

1. Discord server → channel → **Edit Channel** → **Integrations** → **Webhooks** → **New Webhook**.
2. Copy **Webhook URL**.
3. Dán vào mục 10 → 1.

**Lưu ý:** uptime chỉ gửi khi **auto-rejoin đang chạy** (mục 1). Đây không phải service chạy 24/7 độc lập. Nếu muốn uptime liên tục, phải để auto-rejoin chạy.

## 7. Chạy auto-rejoin

Chọn **1**.

Script hỏi:

```text
Chu kỳ reset (phút, Enter=30, 0=tắt):
Delay rejoin (giây, Enter=15):
```

- **Chu kỳ reset**: sau bao nhiêu phút thì tự force-stop và mở lại app. `0` = tắt reset định kỳ.
- **Delay rejoin**: thời gian đếm ngược trước khi mở lại app khi phát hiện văng/mất kết nối. `0` = rejoin ngay.

Script sẽ:

1. Force-stop và mở từng app với link đã cấu hình.
2. Chờ 15 giây khởi động.
3. Kiểm tra PID và log của từng app mỗi 2 giây.
4. Nếu app văng hoặc log báo mất kết nối → đếm ngược → mở lại.
5. Nếu hết chu kỳ reset → mở lại.
6. Gửi uptime + ảnh màn hình lên Discord theo chu kỳ (nếu đã cấu hình).

Nhấn **Ctrl + C** để dừng auto-rejoin và quay lại menu.

### Giữ tool chạy khi đang ở trong Roblox

Khi bạn chuyển sang Roblox, Termux bị đưa xuống nền. Nếu Android tạm dừng hoặc kill Termux, tool sẽ không rejoin được.

- Script tự gọi `termux-wake-lock` khi bắt đầu auto-rejoin (nếu lệnh này có sẵn).
- Nếu vẫn bị dừng, chạy trước khi mở tool:
  ```bash
  termux-wake-lock
  ```
- Vào **Cài đặt Android → Ứng dụng → Termux → Pin** và chọn **Không tối ưu hóa pin / Unrestricted**.
- Không vuốt Termux khỏi recent apps trong lúc auto-rejoin.

### Tool rejoin hoạt động thế nào?

Tool không dùng accessibility, không tự bấm nút trong game. Nó hoạt động ở tầng Android:

1. Đọc `packages.conf` để biết package nào đi với Place ID/link nào.
2. Mở app bằng intent `roblox://placeId=...` (hoặc link server đã nhập).
3. Mỗi 2 giây kiểm tra `pidof <package>` và đọc snapshot `logcat` gần nhất.
4. Nếu **PID không còn** (app crash, bị Android kill, bị force-stop) → coi là `CRASHED` → đếm ngược delay → force-stop và mở lại app.
5. Nếu **PID còn** nhưng logcat của đúng PID đó có mẫu như `Disconnecting from server`, `Connection lost`, `Disconnected from`, `kicked`, `ErrorPrompt` → coi là `DISCONNECTED` → đếm ngược delay → mở lại app.
6. Sau chu kỳ reset (mặc định 30 phút), tool chủ động force-stop và mở lại app để làm mới phiên.
7. Nếu đã cấu hình Discord, tool gửi uptime và ảnh màn hình định kỳ.

**Trả lời ngắn:**
- **App crash / bị kill / văng:** có, tool phát hiện qua PID và mở lại.
- **Mất kết nối khi app vẫn chạy:** có, nếu logcat có mẫu disconnect mà tool nhận biết.
- **Mất mạng hoàn toàn:** tool vẫn có thể mở lại app, nhưng app sẽ không vào được game cho đến khi có mạng.
- **Acc bị logout / cookie hết hạn:** tool chỉ mở lại app, không tự đăng nhập lại. Cần dùng mục 6 để ghi cookie mới.
- **App crash lặp lại liên tục:** tool sẽ mở lại liên tục nhưng không sửa được nguyên nhân crash (app lỗi, dữ liệu hỏng, server chặn).
- **Tool chỉ chạy khi Termux và script còn chạy.** Nếu Termux bị Android kill, máy reboot, hoặc script bị dừng, auto-rejoin dừng theo. Tool không phải service chạy nền vĩnh viễn.
- Việc nhận diện disconnect là **theo mẫu log**, không phải đọc màn hình, nên có thể bỏ sót nếu app đổi log hoặc treo không ghi log.

## 8. Các chức năng khác

### Mở tất cả tab — mục 5

Mở lần lượt các app đã cấu hình với link tương ứng, cách nhau 5 giây.

### Logout Roblox — mục 8

**Cảnh báo: đây là thao tác xoá dữ liệu.**

Script sẽ force-stop app và xoá:

```text
/data/data/<package>/app_webview
/data/data/<package>/shared_prefs
```

Chỉ dùng khi bạn thật sự muốn đăng xuất toàn bộ acc khỏi app đó.

### Export cookie — mục 9

Đọc cookie từ WebView DB và ghi ra:

```text
/sdcard/Download/roblox_sessions_export.txt
```

File này chứa cookie plaintext. **Không chia sẻ, không upload, không gửi qua chat.** Dùng xong nên xoá.

Nếu file export trống, có thể WebView đang dùng `encrypted_value`; script không giải mã được.

### Xem package — mục 11

In **tất cả app đã cài** mà script quét được, gồm app ở user khác và app clone. App Roblox-like được xếp lên trước. Dùng để kiểm tra tên package của app clone.

## 9. Đổi thư mục cấu hình (khuyến nghị)

Mặc định script dùng `/sdcard/Download`, tiện nhưng **không riêng tư** vì bộ nhớ dùng chung. Nếu muốn cấu hình nằm trong home của Termux:

```bash
su -c "IVY_TUN_DIR=/data/data/com.termux/files/home/.ivy-tun bash /sdcard/Download/ivy-tun.sh"
```

Script sẽ tạo thư mục và các file:

```text
packages.conf
profiles.conf
discord.conf
cookie.txt
roblox_sessions_export.txt
ivy-tun.log
```

Tên file cấu hình (`packages.conf`, `profiles.conf`, `discord.conf`, `cookie.txt`, `roblox_sessions_export.txt`) được giữ nguyên để tương thích bản cũ. `IVY_TUN_DIR` là tên mới; nếu bạn vẫn dùng `SHOUKO_DIR` từ bản cũ, script vẫn đọc được. Khi cả hai được đặt, `IVY_TUN_DIR` được ưu tiên.

Có thể đặt biến môi trường trước khi chạy:

```bash
export IVY_TUN_DIR=/data/data/com.termux/files/home/.ivy-tun
bash /sdcard/Download/ivy-tun.sh
```

Tuy nhiên khi script tự gọi `su`, biến môi trường có thể không được giữ. Cách chắc chắn là truyền thẳng vào lệnh `su -c` như trên.

## 10. Kiểm tra và xử lý lỗi

### `sqlite3: command not found`

```bash
pkg install -y sqlite
```

### `curl: command not found`

```bash
pkg install -y curl
```

### `su: not found` / `Permission denied`

- Kiểm tra root bằng `su -c id`; phải trả về `uid=0`.
- Cấp quyền root cho Termux trong Magisk/KernelSU.
- Một số ROM ẩn `su`; thử `which su` hoặc `/system/xbin/su`.

### Không thấy package Roblox/Delta

- Chạy mục 11 để xem **tất cả app đã cài** mà script quét được.
- Từ bản 2.1, script quét cả user hiện tại, `--user 0` và `--user all`, nên app clone ở user khác cũng sẽ hiện.
- Nếu app là bản clone đổi tên package, nhập thẳng package name ở mục 2.
- Kiểm tra app đã cài cho user hiện tại chưa bằng `pm list packages | grep <tên>`, hoặc chạy `su -c "pm list packages --user all -3"`.

### Đã ghi cookie nhưng app vẫn chưa đăng nhập

- App phải được mở ít nhất một lần trước khi ghi cookie.
- Thử force-stop app rồi mở lại.
- Kiểm tra DB có tồn tại:

```bash
su -c "ls -l /data/data/<package>/app_webview/Default/Cookies"
```

- Nếu WebView dùng `encrypted_value`, script không giải mã được. Đăng nhập thủ công hoặc dùng app clone lưu plaintext.
- Một số app dùng DB ở đường dẫn khác; script chỉ hỗ trợ `app_webview/Default` và `app_webview`.

### `am start` mở app nhưng không vào server

- Kiểm tra link ở mục 3.
- Dùng Place ID số hoặc link đầy đủ dạng `https://www.roblox.com/games/<id>/...`.
- Với private server, dùng `roblox://placeId=<id>&linkCode=<code>` nếu app hỗ trợ.
- Một số app clone không nhận intent `roblox://`; thử mở app thủ công.

### Webhook không gửi ảnh

- Kiểm tra `screencap`:

```bash
su -c "screencap -p /sdcard/Download/test.png"
```

- Nếu không có ảnh, script vẫn gửi tin nhắn text.
- Kiểm tra URL webhook còn sống, channel còn tồn tại.
- Discord có rate limit; đừng đặt chu kỳ quá thấp.

### Bấm Leave nhưng tool không rejoin

- Kiểm tra tool còn chạy: Termux không bị Android kill, đã bật `termux-wake-lock` và tắt tối ưu pin.
- Script chỉ phát hiện disconnect nếu logcat có mẫu mà script nhận biết. Chạy lệnh này ngay sau khi bấm Leave để xem log **của đúng PID Roblox**:
  ```bash
  pkg=com.roblox.client
  pids=$(su -c "pidof $pkg")
  echo "PIDs: $pids"
  re=${pids// /|}
  su -c "logcat -d -t 3000 -v threadtime | grep -E '(^| )($re)( |$)' | tail -n 120"
  ```
  Thay `com.roblox.client` bằng package thật của bạn (xem mục 11).
- Nếu log không có mẫu disconnect, tool có thể bỏ sót. Cách xử lý tạm thời: đặt **Chu kỳ reset** ngắn hơn (ví dụ 5 phút) để tool tự mở lại app.
- Nếu app bị treo nhưng PID vẫn còn, tool cũng có thể không phát hiện; cần force-stop hoặc chờ chu kỳ reset.

### Auto-rejoin rejoin liên tục

- Tăng `Delay rejoin` lên 15–30 giây.
- Kiểm tra log app xem có thông báo disconnect thật không.
- Script có cooldown 30 giây sau mỗi lần rejoin; nếu vẫn lặp, app có thể crash ngay khi mở.
- Thử tắt reset định kỳ (`0`) để loại trừ.

### Termux không đọc được `/sdcard/Download`

```bash
termux-setup-storage
```

Cấp quyền storage khi được hỏi. Script chạy bằng root nên thường vẫn đọc được, nhưng Termux cần quyền để bạn chỉnh file.

## 11. Gỡ cài đặt

Xoá script:

```bash
rm -f /sdcard/Download/ivy-tun.sh
```

Xoá cấu hình (cẩn thận, mất profile/cookie):

```bash
rm -f /sdcard/Download/packages.conf
rm -f /sdcard/Download/profiles.conf
rm -f /sdcard/Download/discord.conf
rm -f /sdcard/Download/cookie.txt
rm -f /sdcard/Download/roblox_sessions_export.txt
rm -f /sdcard/Download/ivy-tun.log
```

Nếu dùng `IVY_TUN_DIR` riêng:

```bash
rm -rf /data/data/com.termux/files/home/.ivy-tun
```

## 12. Mã kiểm tra file

Sau khi copy sang điện thoại, có thể kiểm tra:

```bash
sha256sum /sdcard/Download/ivy-tun.sh
```

Hash của bản script đi kèm:

```text
SHA256: ACD4098BFE248D1C8FA8267C6E308299DD05E1EB630D935C954C86E37B9819D0
Bytes:  58283
```

Nếu hash khác, file có thể bị chỉnh sửa hoặc copy lỗi.

## 13. Lưu ý cuối

- Tool này thao tác trực tiếp vào dữ liệu ứng dụng bằng root. Một bản cập nhật Roblox/Delta có thể đổi schema DB hoặc format log làm tool không còn nhận diện đúng.
- Không dùng tool để đăng nhập vào tài khoản không phải của bạn.
- Không chia sẻ cookie, file profile, file export hoặc webhook URL công khai.
- Nên dùng thư mục cấu hình riêng tư thay vì `/sdcard/Download` nếu máy có nhiều app lạ.
