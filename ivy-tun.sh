#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Ivy TUN v2.0
# Optimized multi-account Roblox helper for rooted Android + Termux.
#
# CHỈ DÙNG VỚI THIẾT BỊ VÀ TÀI KHOẢN CỦA BẠN.
# Cookie .ROBLOSECURITY là chìa khóa đăng nhập: không chia sẻ file
# profiles.conf, cookie.txt hoặc file export cho bất kỳ ai.
# ============================================================

set -o pipefail
umask 077

SCRIPT_VERSION="2.0"

# ------------------------------------------------------------
# Đường dẫn
# Mặc định giữ /sdcard/Download để tương thích bản cũ.
# Muốn cấu hình riêng tư hơn:
#   IVY_TUN_DIR=/data/data/com.termux/files/home/.ivy-tun \
#     su -c 'bash /sdcard/Download/ivy-tun.sh'
# SHOUKO_DIR (tên cũ) vẫn được hỗ trợ để tương thích.
# ------------------------------------------------------------
TERMUX_HOME="${TERMUX_HOME:-/data/data/com.termux/files/home}"
[ -d "$TERMUX_HOME" ] || TERMUX_HOME="$HOME"
CONF_DIR="${IVY_TUN_DIR:-${SHOUKO_DIR:-/sdcard/Download}}"
CONF_FILE="$CONF_DIR/packages.conf"
PROFILES_FILE="$CONF_DIR/profiles.conf"
DISCORD_CONF="$CONF_DIR/discord.conf"
COOKIE_INPUT_FILE="$CONF_DIR/cookie.txt"
EXPORT_FILE="$CONF_DIR/roblox_sessions_export.txt"
LOG_FILE="$CONF_DIR/ivy-tun.log"

# ------------------------------------------------------------
# Màu
# ------------------------------------------------------------
if [ -t 1 ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_CYAN=$'\033[1;36m'
    C_GREEN=$'\033[1;32m'
    C_RED=$'\033[1;31m'
    C_YELLOW=$'\033[1;33m'
    C_MAGENTA=$'\033[1;35m'
    C_WHITE=$'\033[1;37m'
    C_GRAY=$'\033[0;90m'
else
    C_RESET=""; C_BOLD=""; C_CYAN=""; C_GREEN=""; C_RED=""
    C_YELLOW=""; C_MAGENTA=""; C_WHITE=""; C_GRAY=""
fi

# ------------------------------------------------------------
# Tự nâng quyền root (không tải code từ Internet)
# ------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    printf '%sCần quyền root để đọc/ghi dữ liệu ứng dụng Roblox.%s\n' "$C_RED" "$C_RESET"
    if [ -f "$0" ]; then
        if ! command -v su >/dev/null 2>&1; then
            printf '%sKhông tìm thấy lệnh su. Hãy cài Magisk/KernelSU và cấp quyền root cho Termux.%s\n' "$C_RED" "$C_RESET"
            exit 1
        fi
        BASH_BIN="${BASH:-/data/data/com.termux/files/usr/bin/bash}"
        [ -x "$BASH_BIN" ] || BASH_BIN="bash"
        SCRIPT_PATH="$0"
        if command -v realpath >/dev/null 2>&1; then
            SCRIPT_PATH="$(realpath "$0" 2>/dev/null || printf '%s' "$0")"
        fi
        printf '%sĐang thử tự nâng quyền bằng su...%s\n' "$C_YELLOW" "$C_RESET"
        exec su -c "$BASH_BIN $(printf '%q ' "$SCRIPT_PATH" "$@")"
    fi
    printf 'Chạy thủ công:\n  su -c "bash /sdcard/Download/ivy-tun.sh"\n'
    exit 1
fi

# ------------------------------------------------------------
# Thêm Termux bin vào PATH.
# Khi chạy qua su, PATH của root có thể không có sqlite3/curl
# dù Termux đã cài. Thêm thư mục chuẩn của Termux vào trước.
# ------------------------------------------------------------
for _prefix in "/data/data/com.termux/files/usr" "${PREFIX:-}"; do
    [ -n "$_prefix" ] || continue
    if [ -d "$_prefix/bin" ]; then
        case ":$PATH:" in
            *":$_prefix/bin:"*) ;;
            *) PATH="$_prefix/bin:$PATH" ;;
        esac
    fi
done
export PATH

# ------------------------------------------------------------
# Khởi tạo file cấu hình
# ------------------------------------------------------------
mkdir -p "$CONF_DIR" 2>/dev/null || {
    printf '%sKhông tạo được thư mục: %s%s\n' "$C_RED" "$CONF_DIR" "$C_RESET"
    exit 1
}
case "$CONF_DIR" in
    /sdcard/*|/storage/*) ;;
    *) chmod 700 "$CONF_DIR" 2>/dev/null ;;
esac

for _f in "$CONF_FILE" "$PROFILES_FILE" "$DISCORD_CONF" "$COOKIE_INPUT_FILE"; do
    [ -f "$_f" ] || : > "$_f"
    chmod 600 "$_f" 2>/dev/null
done

# ------------------------------------------------------------
# Kiểm tra công cụ
# ------------------------------------------------------------
_missing=()
for _cmd in sqlite3 curl am pm pidof logcat; do
    command -v "$_cmd" >/dev/null 2>&1 || _missing+=("$_cmd")
done
if [ "${#_missing[@]}" -gt 0 ]; then
    printf '%sThiếu lệnh: %s%s\n' "$C_RED" "${_missing[*]}" "$C_RESET"
    printf 'Cài trong Termux:\n'
    printf '  pkg update -y && pkg install -y sqlite curl\n'
    printf 'Nếu thiếu am/pm/pidof/logcat: kiểm tra lại root hoặc ROM Android.\n'
    exit 1
fi

HAS_TPUT=1
command -v tput >/dev/null 2>&1 || HAS_TPUT=0
HAS_SCREENCAP=1
command -v screencap >/dev/null 2>&1 || HAS_SCREENCAP=0
HAS_MONKEY=1
command -v monkey >/dev/null 2>&1 || HAS_MONKEY=0

# ------------------------------------------------------------
# Biến toàn cục cho auto rejoin / webhook uptime
# ------------------------------------------------------------
UPTIME_PID=""
AUTO_RUNNING=0
IN_AUTO=0
LOGCAT_SNAPSHOT=""

# ------------------------------------------------------------
# Hàm tiện ích
# ------------------------------------------------------------
log_line() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null
}

msg() {
    printf '%s%s%s\n' "$C_CYAN" "$*" "$C_RESET"
    log_line "INFO $*"
}

ok_msg() {
    printf '%s[✓] %s%s\n' "$C_GREEN" "$*" "$C_RESET"
    log_line "OK $*"
}

warn_msg() {
    printf '%s[!] %s%s\n' "$C_RED" "$*" "$C_RESET" >&2
    log_line "WARN $*"
}

pause_key() {
    printf '\n%sBấm Enter để tiếp tục...%s' "$C_WHITE" "$C_RESET"
    read -r _
}

is_valid_pkg() {
    [[ "$1" =~ ^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$ ]]
}

mask_secret() {
    local s="$1"
    if [ "${#s}" -le 16 ]; then
        printf '***'
    else
        printf '%s...%s' "${s:0:8}" "${s: -4}"
    fi
}

make_tmp() {
    local f="$CONF_DIR/.tmp.$$.$RANDOM"
    : > "$f"
    printf '%s' "$f"
}

# Đọc 1 khóa trong file cấu hình dạng KEY=VALUE
conf_get() {
    local file="$1" key="$2" line k v
    [ -f "$file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        case "$line" in *=*) ;; *) continue ;; esac
        k="${line%%=*}"
        v="${line#*=}"
        v="${v%$'\r'}"
        if [ "$k" = "$key" ]; then
            printf '%s' "$v"
            return 0
        fi
    done < "$file"
    return 1
}

# Ghi/ghi đè 1 khóa, giữ nguyên các dòng khác
conf_set() {
    local file="$1" key="$2" value="$3" line tmp
    tmp="$(make_tmp)" || return 1
    if [ -f "$file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [ -z "$line" ] && continue
            line="${line%$'\r'}"
            case "$line" in *=*) ;; *) continue ;; esac
            [ "${line%%=*}" = "$key" ] && continue
            printf '%s\n' "$line" >> "$tmp"
        done < "$file"
    fi
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    if ! mv "$tmp" "$file"; then
        rm -f "$tmp"
        return 1
    fi
    chmod 600 "$file" 2>/dev/null
}

# Xóa 1 khóa
conf_del() {
    local file="$1" key="$2" line tmp
    tmp="$(make_tmp)" || return 1
    if [ -f "$file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [ -z "$line" ] && continue
            line="${line%$'\r'}"
            case "$line" in *=*) ;; *) continue ;; esac
            [ "${line%%=*}" = "$key" ] && continue
            printf '%s\n' "$line" >> "$tmp"
        done < "$file"
    fi
    if ! mv "$tmp" "$file"; then
        rm -f "$tmp"
        return 1
    fi
    chmod 600 "$file" 2>/dev/null
}

# ------------------------------------------------------------
# Danh sách package
# ------------------------------------------------------------
get_all_installed_roblox() {
    local all rbx
    all="$(pm list packages -3 2>/dev/null | sed 's/^package://' | tr -d '\r' | sort -u)"
    if [ -z "$all" ]; then
        all="$(pm list packages --user all -3 2>/dev/null | sed 's/^package://' | tr -d '\r' | sort -u)"
    fi
    [ -z "$all" ] && return 0

    rbx="$(printf '%s\n' "$all" | grep -iE 'roblox|delta|deltb|fluxus|hydrogen|codex|arceus|rejoin|rbx' || true)"
    if [ -n "$rbx" ]; then
        printf '%s\n' "$rbx"
    else
        printf '%s\n' "$all" | grep -vE '^(com\.termux|bin\.mt\.plus|com\.og\.|com\.android|org\.telegram|com\.google\.)' || true
    fi
}

# In danh sách có số thứ tự, trả về package được chọn qua stdout
select_package() {
    local prompt="${1:-Chọn package}"
    local -a pkgs=()
    local i sel

    mapfile -t pkgs < <(get_all_installed_roblox)
    if [ "${#pkgs[@]}" -eq 0 ]; then
        warn_msg "Không tìm thấy package nào."
        return 1
    fi

    for i in "${!pkgs[@]}"; do
        printf '  %s[%d]%s %s\n' "$C_MAGENTA" "$((i + 1))" "$C_RESET" "${pkgs[$i]}" >&2
    done

    printf '%s%s (0=hủy, hoặc nhập package name): %s' "$C_GREEN" "$prompt" "$C_RESET" >&2
    read -r sel
    [ -z "$sel" ] && return 1
    [ "$sel" = "0" ] && return 1

    if [[ "$sel" =~ ^[0-9]+$ ]]; then
        local idx=$((sel - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#pkgs[@]}" ]; then
            printf '%s' "${pkgs[$idx]}"
            return 0
        fi
        warn_msg "Số thứ tự không hợp lệ."
        return 1
    fi

    if is_valid_pkg "$sel"; then
        printf '%s' "$sel"
        return 0
    fi
    warn_msg "Package name không hợp lệ."
    return 1
}

# ------------------------------------------------------------
# Parse link server -> intent Roblox
# ------------------------------------------------------------
parse_server_intent() {
    local link="$1" pid code
    link="${link//$'\r'/}"
    link="${link// /}"

    [ -z "$link" ] && return 1

    if [[ "$link" =~ ^[0-9]+$ ]]; then
        printf 'roblox://placeId=%s' "$link"
        return 0
    fi

    pid="$(printf '%s' "$link" | grep -oE '(placeId=|games/)[0-9]+' | head -n 1 | grep -oE '[0-9]+')"
    code="$(printf '%s' "$link" | grep -oE 'linkCode=[A-Za-z0-9_-]+' | head -n 1 | cut -d'=' -f2)"

    if [ -n "$pid" ]; then
        if [ -n "$code" ]; then
            printf 'roblox://placeId=%s&linkCode=%s' "$pid" "$code"
        else
            printf 'roblox://placeId=%s' "$pid"
        fi
        return 0
    fi

    if [[ "$link" == roblox://* ]]; then
        printf '%s' "$link"
        return 0
    fi

    printf 'roblox://placeId=%s' "$link"
}

open_package_tab() {
    local pkg="$1" link="$2" intent
    [ "$link" = "0" ] && link=""
    if [ -n "$link" ]; then
        intent="$(parse_server_intent "$link")"
        am start -p "$pkg" -a android.intent.action.VIEW -d "$intent" >/dev/null 2>&1
    elif [ "$HAS_MONKEY" -eq 1 ]; then
        monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    else
        am start -p "$pkg" >/dev/null 2>&1
    fi
}

launch_package() {
    local pkg="$1" link="$2"
    [ "$link" = "0" ] && link=""
    am force-stop "$pkg" >/dev/null 2>&1
    input keyevent 4 >/dev/null 2>&1
    sleep 1
    [ "$AUTO_RUNNING" -eq 1 ] || return 1
    open_package_tab "$pkg" "$link"
}

# ------------------------------------------------------------
# Roblox API
# ------------------------------------------------------------
verify_cookie() {
    local cookie="$1" res uid uname dname
    res="$(curl -fsS --max-time 20 \
        -H "Cookie: .ROBLOSECURITY=$cookie" \
        -H "User-Agent: Mozilla/5.0 (Linux; Android 10)" \
        'https://users.roblox.com/v1/users/authenticated' 2>/dev/null)" || {
        printf 'INVALID|||'
        return 0
    }

    uid="$(printf '%s' "$res" | grep -oE '"id"[[:space:]]*:[[:space:]]*[0-9]+' | head -n 1 | grep -oE '[0-9]+')"
    uname="$(printf '%s' "$res" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    dname="$(printf '%s' "$res" | sed -n 's/.*"displayName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

    if [ -n "$uid" ] && [ "$uid" -gt 0 ] 2>/dev/null; then
        printf 'VALID|%s|%s|%s' "$uid" "$uname" "$dname"
    else
        printf 'INVALID|||'
    fi
}

# ------------------------------------------------------------
# Ghi cookie vào WebView DB
# ------------------------------------------------------------
apply_cookie_to_pkg() {
    local pkg="$1" cookie="$2"

    is_valid_pkg "$pkg" || { warn_msg "Package không hợp lệ: $pkg"; return 1; }
    [ -d "/data/data/$pkg" ] || { warn_msg "Không thấy /data/data/$pkg"; return 1; }

    local db_dir="/data/data/$pkg/app_webview/Default"
    local db="$db_dir/Cookies"

    am force-stop "$pkg" >/dev/null 2>&1
    sleep 1

    mkdir -p "$db_dir" 2>/dev/null || {
        warn_msg "Không tạo được $db_dir"
        return 1
    }

    sqlite3 "$db" "CREATE TABLE IF NOT EXISTS cookies(creation_utc INTEGER NOT NULL, host_key TEXT NOT NULL, name TEXT NOT NULL, value TEXT NOT NULL, path TEXT NOT NULL, expires_utc INTEGER NOT NULL, is_secure INTEGER NOT NULL, is_httponly INTEGER NOT NULL, last_access_utc INTEGER NOT NULL, has_expires INTEGER NOT NULL, is_persistent INTEGER NOT NULL, priority INTEGER NOT NULL, encrypted_value BLOB DEFAULT '', samesite INTEGER NOT NULL, source_scheme INTEGER NOT NULL, source_port INTEGER NOT NULL, is_same_party INTEGER NOT NULL, PRIMARY KEY(host_key, name, path));" 2>/dev/null

    local now webkit expire escaped cols
    now="$(date +%s)"
    webkit=$(( (now + 11644473600) * 1000000 ))
    expire=$(( webkit + 315360000000000 ))
    escaped="${cookie//\'/\'\'}"

    cols="$(sqlite3 "$db" "PRAGMA table_info(cookies);" 2>/dev/null | cut -d'|' -f2 | tr -d '\r')"
    [ -n "$cols" ] || { warn_msg "Không đọc được schema Cookies."; return 1; }
    if ! printf '%s\n' "$cols" | grep -qx 'value'; then
        warn_msg "Bảng cookies không có cột value; WebView có thể dùng mã hoá."
        return 1
    fi

    local col_list="" val_list=""
    add_col() {
        if printf '%s\n' "$cols" | grep -qx "$1"; then
            col_list="${col_list}${col_list:+,}$1"
            val_list="${val_list}${val_list:+,}$2"
        fi
    }

    add_col creation_utc "$webkit"
    add_col host_key "'.roblox.com'"
    add_col name "'.ROBLOSECURITY'"
    add_col value "'$escaped'"
    add_col path "'/'"
    add_col expires_utc "$expire"
    add_col is_secure "1"
    add_col is_httponly "1"
    add_col last_access_utc "$webkit"
    add_col has_expires "1"
    add_col is_persistent "1"
    add_col priority "1"
    add_col encrypted_value "''"
    add_col samesite "-1"
    add_col source_scheme "2"
    add_col source_port "443"
    add_col is_same_party "0"

    [ -n "$col_list" ] || { warn_msg "Schema Cookies không có cột phù hợp."; return 1; }

    if ! sqlite3 "$db" "BEGIN; DELETE FROM cookies WHERE name='.ROBLOSECURITY'; INSERT OR REPLACE INTO cookies ($col_list) VALUES ($val_list); COMMIT;" 2>/dev/null; then
        warn_msg "Ghi cookie thất bại (DB đang bị khoá?)."
        sqlite3 "$db" "ROLLBACK;" >/dev/null 2>&1 || true
        return 1
    fi

    local app_uid
    app_uid="$(stat -c '%u' "/data/data/$pkg" 2>/dev/null)"
    if [ -z "$app_uid" ]; then
        app_uid="$(ls -nd "/data/data/$pkg" 2>/dev/null | awk '{print $3}')"
    fi
    if [ -n "$app_uid" ]; then
        chown "$app_uid:$app_uid" "/data/data/$pkg/app_webview" "$db_dir" "$db" 2>/dev/null
        chmod 771 "/data/data/$pkg/app_webview" "$db_dir" 2>/dev/null
        for _suffix in -journal -wal -shm; do
            [ -f "$db$_suffix" ] && chown "$app_uid:$app_uid" "$db$_suffix" 2>/dev/null
        done
        chmod 660 "$db" 2>/dev/null
    fi

    if command -v restorecon >/dev/null 2>&1; then
        restorecon "$db" >/dev/null 2>&1 || true
    fi

    return 0
}

# ------------------------------------------------------------
# Discord webhook
# ------------------------------------------------------------
get_webhook_url() {
    conf_get "$DISCORD_CONF" WEBHOOK_URL 2>/dev/null
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

send_webhook() {
    local title="$1" desc="$2" color="${3:-5814783}"
    local url now_str title_j desc_j footer_j payload shot
    url="$(get_webhook_url)"
    [ -z "$url" ] && return 1

    case "$url" in
        https://discord.com/api/webhooks/*|https://discordapp.com/api/webhooks/*|https://canary.discord.com/api/webhooks/*|https://ptb.discord.com/api/webhooks/*)
            ;;
        *)
            warn_msg "Webhook URL không hợp lệ (phải là Discord webhook)."
            return 1
            ;;
    esac

    now_str="$(date '+%H:%M:%S %d/%m/%Y')"
    title_j="$(json_escape "$title")"
    desc_j="$(json_escape "$desc")"
    footer_j="$(json_escape "Ivy TUN • $now_str")"

    shot="$CONF_DIR/.webhook_shot.$$.$RANDOM.png"
    if [ "$HAS_SCREENCAP" -eq 1 ]; then
        screencap -p "$shot" >/dev/null 2>&1 || true
    fi

    if [ -s "$shot" ]; then
        payload="$(printf '{"embeds":[{"title":"%s","description":"%s","color":%s,"image":{"url":"attachment://screenshot.png"},"footer":{"text":"%s"}}]}' \
            "$title_j" "$desc_j" "$color" "$footer_j")"
        if curl -fsS --max-time 30 \
            --form-string "payload_json=$payload" \
            -F "file=@$shot;filename=screenshot.png" \
            "$url" >/dev/null 2>&1; then
            rm -f "$shot"
            return 0
        fi
    fi

    payload="$(printf '{"embeds":[{"title":"%s","description":"%s","color":%s,"footer":{"text":"%s"}}]}' \
        "$title_j" "$desc_j" "$color" "$footer_j")"
    rm -f "$shot"
    curl -fsS --max-time 30 -H 'Content-Type: application/json' -d "$payload" "$url" >/dev/null 2>&1
}

stop_uptime() {
    if [ -n "${UPTIME_PID:-}" ]; then
        kill "$UPTIME_PID" 2>/dev/null || true
        if command -v pkill >/dev/null 2>&1; then
            pkill -P "$UPTIME_PID" 2>/dev/null || true
        fi
        UPTIME_PID=""
    fi
}

cleanup() {
    stop_uptime
    if [ "$HAS_TPUT" -eq 1 ]; then
        tput cnorm 2>/dev/null || printf '\033[?25h'
    else
        printf '\033[?25h'
    fi
    printf '%s' "$C_RESET"
    clear 2>/dev/null || true
    exit 0
}

handle_int() {
    if [ "$IN_AUTO" -eq 1 ]; then
        AUTO_RUNNING=0
        printf '\n%sĐang dừng auto rejoin...%s\n' "$C_YELLOW" "$C_RESET"
    else
        cleanup
    fi
}

trap handle_int INT
trap cleanup TERM

# ------------------------------------------------------------
# Quản lý Discord webhook
# ------------------------------------------------------------
manage_discord_webhook() {
    while true; do
        clear
        local url interval shown
        url="$(get_webhook_url)"
        interval="$(conf_get "$DISCORD_CONF" INTERVAL 2>/dev/null)"
        interval="${interval:-15}"

        printf '%s┌── [ DISCORD WEBHOOK & UPTIME ] ──────────┐%s\n' "$C_CYAN" "$C_RESET"
        if [ -n "$url" ]; then
            shown="$(mask_secret "$url")"
            printf ' %s[✓] Webhook:%s %s\n' "$C_GREEN" "$C_RESET" "$shown"
        else
            printf ' %s[!] Webhook:%s Chưa cài đặt\n' "$C_RED" "$C_RESET"
        fi
        printf ' %s• Chu kỳ uptime:%s %s phút\n' "$C_YELLOW" "$C_RESET" "$interval"
        printf ' %s• Gửi uptime khi auto rejoin đang chạy.%s\n' "$C_GRAY" "$C_RESET"
        printf '%s├── Chức năng ──────────────────────────────┤%s\n' "$C_CYAN" "$C_RESET"
        printf '│ %s1%s  Nhập URL Webhook mới\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s2%s  Đổi chu kỳ uptime (phút)\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s3%s  Test gửi ảnh + thông báo\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s4%s  Xóa cấu hình webhook\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s0%s  Quay lại\n' "$C_MAGENTA" "$C_RESET"
        printf '%s└───────────────────────────────────────────┘%s\n\n' "$C_CYAN" "$C_RESET"

        printf '%sLựa chọn: %s' "$C_WHITE" "$C_RESET"
        read -r choice

        case "$choice" in
            1)
                printf '%sDán Discord Webhook URL: %s' "$C_WHITE" "$C_RESET"
                read -r new_url
                new_url="${new_url//$'\r'/}"
                new_url="${new_url# }"
                new_url="${new_url% }"
                if [ -n "$new_url" ]; then
                    case "$new_url" in
                        https://discord.com/api/webhooks/*|https://discordapp.com/api/webhooks/*|https://canary.discord.com/api/webhooks/*|https://ptb.discord.com/api/webhooks/*)
                            conf_set "$DISCORD_CONF" WEBHOOK_URL "$new_url"
                            if [ -z "$(conf_get "$DISCORD_CONF" INTERVAL 2>/dev/null)" ]; then
                                conf_set "$DISCORD_CONF" INTERVAL 15
                            fi
                            ok_msg "Đã lưu webhook."
                            ;;
                        *)
                            warn_msg "URL không đúng dạng Discord webhook."
                            ;;
                    esac
                fi
                sleep 1
                ;;
            2)
                printf '%sChu kỳ uptime (phút, 1-1440): %s' "$C_WHITE" "$C_RESET"
                read -r new_min
                if [[ "$new_min" =~ ^[0-9]+$ ]] && [ "$new_min" -ge 1 ] && [ "$new_min" -le 1440 ]; then
                    conf_set "$DISCORD_CONF" INTERVAL "$new_min"
                    ok_msg "Đã đổi chu kỳ: $new_min phút."
                else
                    warn_msg "Giá trị không hợp lệ."
                fi
                sleep 1
                ;;
            3)
                if [ -z "$url" ]; then
                    warn_msg "Chưa cấu hình webhook."
                    sleep 2
                else
                    printf '%sĐang gửi test...%s\n' "$C_YELLOW" "$C_RESET"
                    if send_webhook "🧪 Ivy TUN Test Webhook" \
                        "Báo cáo kiểm tra kết nối từ Termux Android.
- Thời gian: $(date '+%H:%M:%S %d/%m/%Y')
- Trạng thái: Hoạt động bình thường" 3066993; then
                        ok_msg "Đã gửi test."
                    else
                        warn_msg "Gửi thất bại. Kiểm tra URL/mạng."
                    fi
                    sleep 2
                fi
                ;;
            4)
                conf_del "$DISCORD_CONF" WEBHOOK_URL
                conf_del "$DISCORD_CONF" INTERVAL
                ok_msg "Đã xóa cấu hình webhook."
                sleep 1
                ;;
            0|"")
                break
                ;;
        esac
    done
}

# ------------------------------------------------------------
# Profiles
# ------------------------------------------------------------
# File mới dùng TAB. File cũ dùng | vẫn đọc được.
parse_profile_line() {
    local line="$1" rest
    P_PKG=""; P_UNAME=""; P_UID=""; P_PLACE=""; P_COOKIE=""
    [ -z "$line" ] && return 1

    if [[ "$line" == *$'\t'* ]]; then
        P_PKG="${line%%$'\t'*}"
        rest="${line#*$'\t'}"
        P_UNAME="${rest%%$'\t'*}"
        rest="${rest#*$'\t'}"
        P_UID="${rest%%$'\t'*}"
        rest="${rest#*$'\t'}"
        P_PLACE="${rest%%$'\t'*}"
        P_COOKIE="${rest#*$'\t'}"
    else
        P_PKG="${line%%|*}"
        rest="${line#*|}"
        P_UNAME="${rest%%|*}"
        rest="${rest#*|}"
        P_UID="${rest%%|*}"
        rest="${rest#*|}"
        P_PLACE="${rest%%|*}"
        P_COOKIE="${rest#*|}"
    fi
    P_PKG="${P_PKG%$'\r'}"
    P_UNAME="${P_UNAME%$'\r'}"
    P_UID="${P_UID%$'\r'}"
    P_PLACE="${P_PLACE%$'\r'}"
    P_COOKIE="${P_COOKIE%$'\r'}"
    [ -n "$P_PKG" ]
}

profile_remove_pkg() {
    local want="$1" line tmp
    tmp="$(make_tmp)" || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        line="${line%$'\r'}"
        if ! parse_profile_line "$line"; then
            printf '%s\n' "$line" >> "$tmp"
            continue
        fi
        [ "$P_PKG" = "$want" ] || printf '%s\n' "$line" >> "$tmp"
    done < "$PROFILES_FILE"
    mv "$tmp" "$PROFILES_FILE"
    chmod 600 "$PROFILES_FILE" 2>/dev/null
}

profile_add() {
    local pkg cookie check status uid uname place
    pkg="$(select_package 'Chọn package cho profile')" || return 0

    printf '%sDán cookie .ROBLOSECURITY: %s' "$C_WHITE" "$C_RESET"
    read -r cookie
    cookie="${cookie//$'\r'/}"
    cookie="${cookie# }"
    cookie="${cookie% }"
    [ -z "$cookie" ] && return 0

    printf '%sĐang kiểm tra cookie...%s\n' "$C_YELLOW" "$C_RESET"
    check="$(verify_cookie "$cookie")"
    status="${check%%|*}"
    uid="$(printf '%s' "$check" | cut -d'|' -f2)"
    uname="$(printf '%s' "$check" | cut -d'|' -f3)"

    if [ "$status" != "VALID" ]; then
        warn_msg "Cookie không hợp lệ hoặc đã hết hạn."
        sleep 2
        return 1
    fi
    ok_msg "Hợp lệ: $uname (ID: $uid)"

    printf '%sPlace ID/Link server (Enter = 0): %s' "$C_WHITE" "$C_RESET"
    read -r place
    place="${place//$'\r'/}"
    [ -z "$place" ] && place="0"

    profile_remove_pkg "$pkg"
    printf '%s\t%s\t%s\t%s\t%s\n' "$pkg" "$uname" "$uid" "$place" "$cookie" >> "$PROFILES_FILE"
    chmod 600 "$PROFILES_FILE" 2>/dev/null
    ok_msg "Đã lưu profile $pkg."
}

manage_account_profiles() {
    while true; do
        clear
        printf '%s┌── [ QUẢN LÝ ACC THEO PROFILE ] ──────────┐%s\n' "$C_CYAN" "$C_RESET"
        if [ ! -s "$PROFILES_FILE" ]; then
            printf ' %sChưa có profile nào.%s\n' "$C_GRAY" "$C_RESET"
        else
            local idx=0 line
            while IFS= read -r line || [ -n "$line" ]; do
                [ -z "$line" ] && continue
                parse_profile_line "$line" || continue
                idx=$((idx + 1))
                printf ' %s[%d]%s %s%s%s (%s - ID: %s)\n' \
                    "$C_YELLOW" "$idx" "$C_RESET" "$C_CYAN" "$P_PKG" "$C_RESET" "${P_UNAME:-Unknown}" "${P_UID:-N/A}"
                printf '     %sPlace: %s | Cookie: %s%s\n' \
                    "$C_GRAY" "${P_PLACE:0:24}" "$(mask_secret "$P_COOKIE")" "$C_RESET"
            done < "$PROFILES_FILE"
        fi
        printf '%s├── Chức năng ─────────────────────────────┤%s\n' "$C_CYAN" "$C_RESET"
        printf '│ %s1%s  Thêm profile (verify cookie)\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s2%s  Đồng bộ profile -> packages.conf\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s3%s  Nạp cookie từ tất cả profile\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s4%s  Xóa một profile\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s5%s  Xóa toàn bộ profile\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s0%s  Quay lại\n' "$C_MAGENTA" "$C_RESET"
        printf '%s└──────────────────────────────────────────┘%s\n\n' "$C_CYAN" "$C_RESET"

        printf '%sLựa chọn: %s' "$C_WHITE" "$C_RESET"
        read -r choice

        case "$choice" in
            1)
                profile_add
                sleep 1
                ;;
            2)
                if [ ! -s "$PROFILES_FILE" ]; then
                    warn_msg "Chưa có profile."
                    sleep 2
                    continue
                fi
                : > "$CONF_FILE"
                while IFS= read -r line || [ -n "$line" ]; do
                    [ -z "$line" ] && continue
                    parse_profile_line "$line" || continue
                    is_valid_pkg "$P_PKG" || continue
                    [ -n "$P_PLACE" ] || P_PLACE="0"
                    printf '%s=%s\n' "$P_PKG" "$P_PLACE" >> "$CONF_FILE"
                done < "$PROFILES_FILE"
                chmod 600 "$CONF_FILE" 2>/dev/null
                ok_msg "Đã đồng bộ profile vào packages.conf."
                sleep 2
                ;;
            3)
                if [ ! -s "$PROFILES_FILE" ]; then
                    warn_msg "Chưa có profile."
                    sleep 2
                    continue
                fi
                while IFS= read -r line || [ -n "$line" ]; do
                    [ -z "$line" ] && continue
                    parse_profile_line "$line" || continue
                    [ -z "$P_COOKIE" ] && continue
                    if apply_cookie_to_pkg "$P_PKG" "$P_COOKIE"; then
                        ok_msg "Đã nạp cookie: $P_PKG (${P_UNAME:-?})"
                    else
                        warn_msg "Lỗi nạp cookie: $P_PKG"
                    fi
                done < "$PROFILES_FILE"
                pause_key
                ;;
            4)
                if [ ! -s "$PROFILES_FILE" ]; then
                    warn_msg "Chưa có profile."
                    sleep 2
                    continue
                fi
                printf '%sSố thứ tự profile cần xóa: %s' "$C_WHITE" "$C_RESET"
                read -r del_idx
                if [[ "$del_idx" =~ ^[0-9]+$ ]] && [ "$del_idx" -gt 0 ]; then
                    local tmp line count=0
                    tmp="$(make_tmp)"
                    while IFS= read -r line || [ -n "$line" ]; do
                        [ -z "$line" ] && continue
                        count=$((count + 1))
                        [ "$count" -eq "$del_idx" ] || printf '%s\n' "$line" >> "$tmp"
                    done < "$PROFILES_FILE"
                    mv "$tmp" "$PROFILES_FILE"
                    chmod 600 "$PROFILES_FILE" 2>/dev/null
                    ok_msg "Đã xóa profile số $del_idx."
                else
                    warn_msg "Số không hợp lệ."
                fi
                sleep 1
                ;;
            5)
                : > "$PROFILES_FILE"
                ok_msg "Đã xóa toàn bộ profile."
                sleep 1
                ;;
            0|"")
                break
                ;;
        esac
    done
}

# ------------------------------------------------------------
# Chọn package & gán link
# ------------------------------------------------------------
select_packages_assign_link() {
    while true; do
        clear
        local pkg link
        pkg="$(select_package 'Chọn package')" || break
        printf '%sPlace ID/Link cho %s%s%s: %s' "$C_WHITE" "$C_YELLOW" "$pkg" "$C_WHITE" "$C_RESET"
        read -r link
        link="${link//$'\r'/}"
        if [ -z "$link" ]; then
            warn_msg "Link trống, bỏ qua."
            sleep 1
            continue
        fi
        conf_set "$CONF_FILE" "$pkg" "$link"
        ok_msg "Đã lưu $pkg"
        sleep 1
    done
}

list_selected_packages() {
    clear
    printf '%s┌── [ PACKAGES ĐÃ CẤU HÌNH ] ──────────────┐%s\n' "$C_CYAN" "$C_RESET"
    if [ ! -s "$CONF_FILE" ]; then
        warn_msg "Chưa có package nào."
    else
        local idx=0 line pkg link
        while IFS= read -r line || [ -n "$line" ]; do
            [ -z "$line" ] && continue
            case "$line" in *=*) ;; *) continue ;; esac
            pkg="${line%%=*}"
            link="${line#*=}"
            pkg="${pkg%$'\r'}"
            link="${link%$'\r'}"
            idx=$((idx + 1))
            printf ' %s%d.%s %s\n' "$C_YELLOW" "$idx" "$C_RESET" "$pkg"
            printf '    %sLink:%s %s\n' "$C_GRAY" "$C_GREEN" "${link:0:50}"
        done < "$CONF_FILE"
    fi
    printf '%s└──────────────────────────────────────────┘%s\n' "$C_CYAN" "$C_RESET"
    printf ' %sFile: %s%s\n' "$C_GRAY" "$CONF_FILE" "$C_RESET"
    pause_key
}

auto_select_all_one_link() {
    clear
    printf '%s┌── [ GÁN TẤT CẢ CHUNG 1 LINK ] ──────────┐%s\n' "$C_CYAN" "$C_RESET"
    local -a pkgs=()
    local p link
    mapfile -t pkgs < <(get_all_installed_roblox)
    if [ "${#pkgs[@]}" -eq 0 ]; then
        warn_msg "Không có package."
        pause_key
        return
    fi
    for p in "${pkgs[@]}"; do printf '  %s•%s %s\n' "$C_GRAY" "$C_RESET" "$p"; done
    printf '%s└──────────────────────────────────────────┘%s\n' "$C_CYAN" "$C_RESET"

    printf '\n%sPlace ID/Link dùng chung (0=hủy): %s' "$C_WHITE" "$C_RESET"
    read -r link
    link="${link//$'\r'/}"
    if [ -z "$link" ] || [ "$link" = "0" ]; then
        return
    fi

    : > "$CONF_FILE"
    for p in "${pkgs[@]}"; do
        printf '%s=%s\n' "$p" "$link" >> "$CONF_FILE"
    done
    chmod 600 "$CONF_FILE" 2>/dev/null
    ok_msg "Đã gán tất cả package."
    sleep 2
}

open_all_tabs() {
    clear
    if [ ! -s "$CONF_FILE" ]; then
        warn_msg "Chưa cấu hình package. Vào mục 2 trước."
        pause_key
        return
    fi
    printf '%s┌── [ MỞ TOÀN BỘ TABS ROBLOX ] ───────────┐%s\n' "$C_CYAN" "$C_RESET"
    local line pkg link
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        case "$line" in *=*) ;; *) continue ;; esac
        pkg="${line%%=*}"
        link="${line#*=}"
        pkg="${pkg%$'\r'}"
        link="${link%$'\r'}"
        is_valid_pkg "$pkg" || continue
        printf ' %s→%s %s\n' "$C_YELLOW" "$C_RESET" "$pkg"
        open_package_tab "$pkg" "$link"
        sleep 5
    done < "$CONF_FILE"
    ok_msg "Đã mở xong các tab."
    pause_key
}

# ------------------------------------------------------------
# Login cookie
# ------------------------------------------------------------
login_via_cookie() {
    clear
    printf '%s┌── [ LOGIN VIA COOKIE ] ──────────────────┐%s\n' "$C_CYAN" "$C_RESET"
    printf ' %s1.%s Nạp từ file cookie.txt (theo thứ tự package)\n' "$C_YELLOW" "$C_RESET"
    printf ' %s2.%s Chọn package và nhập cookie\n' "$C_YELLOW" "$C_RESET"
    printf ' %s0.%s Quay lại\n' "$C_YELLOW" "$C_RESET"
    printf '%s└──────────────────────────────────────────┘%s\n' "$C_CYAN" "$C_RESET"
    printf ' %sFile: %s%s\n\n' "$C_GRAY" "$COOKIE_INPUT_FILE" "$C_RESET"
    printf '%sChọn: %s' "$C_WHITE" "$C_RESET"
    read -r method

    case "$method" in
        1)
            if [ ! -s "$COOKIE_INPUT_FILE" ]; then
                warn_msg "File cookie.txt trống."
                sleep 2
                return
            fi
            local -a pkgs=()
            local line pkg idx=0 check status uname cookie
            mapfile -t pkgs < <(get_all_installed_roblox)
            if [ "${#pkgs[@]}" -eq 0 ]; then
                warn_msg "Không có package."
                pause_key
                return
            fi
            while IFS= read -r line || [ -n "$line" ]; do
                [ -z "$line" ] && continue
                cookie="${line//$'\r'/}"
                cookie="${cookie# }"
                cookie="${cookie% }"
                [ -z "$cookie" ] && continue
                pkg="${pkgs[$idx]:-}"
                idx=$((idx + 1))
                [ -z "$pkg" ] && continue
                check="$(verify_cookie "$cookie")"
                status="${check%%|*}"
                uname="$(printf '%s' "$check" | cut -d'|' -f3)"
                printf ' %s→ Dòng %d: %s%s\n' "$C_YELLOW" "$idx" "$pkg" "$C_RESET"
                if [ "$status" = "VALID" ]; then
                    ok_msg "Cookie hợp lệ: $uname"
                else
                    warn_msg "Cookie không hợp lệ, vẫn ghi vào $pkg"
                fi
                apply_cookie_to_pkg "$pkg" "$cookie" || warn_msg "Ghi thất bại: $pkg"
                sleep 1
            done < "$COOKIE_INPUT_FILE"
            ok_msg "Hoàn tất nạp cookie."
            pause_key
            ;;
        2)
            local pkg cookie check status uname
            pkg="$(select_package 'Chọn package')" || return
            printf '%sDán cookie .ROBLOSECURITY: %s' "$C_WHITE" "$C_RESET"
            read -r cookie
            cookie="${cookie//$'\r'/}"
            cookie="${cookie# }"
            cookie="${cookie% }"
            [ -z "$cookie" ] && return
            check="$(verify_cookie "$cookie")"
            status="${check%%|*}"
            uname="$(printf '%s' "$check" | cut -d'|' -f3)"
            if [ "$status" = "VALID" ]; then
                ok_msg "Hợp lệ: $uname"
            else
                warn_msg "Cookie không hợp lệ, vẫn ghi."
            fi
            if apply_cookie_to_pkg "$pkg" "$cookie"; then
                ok_msg "Đã nạp cookie vào $pkg."
            else
                warn_msg "Nạp cookie thất bại."
            fi
            pause_key
            ;;
        0|"")
            return
            ;;
    esac
}

# ------------------------------------------------------------
# Logout
# ------------------------------------------------------------
logout_roblox() {
    clear
    local -a pkgs=()
    local p pkg choice
    mapfile -t pkgs < <(get_all_installed_roblox)
    if [ "${#pkgs[@]}" -eq 0 ]; then
        warn_msg "Không có package."
        pause_key
        return
    fi

    local i=0
    for p in "${pkgs[@]}"; do
        i=$((i + 1))
        printf '  %s[%d]%s %s\n' "$C_MAGENTA" "$i" "$C_RESET" "$p"
    done
    printf '  %s[A]%s Logout TẤT CẢ\n' "$C_MAGENTA" "$C_RESET"
    printf '  %s[0]%s Quay lại\n\n' "$C_MAGENTA" "$C_RESET"

    printf '%sChọn package (số/A/0): %s' "$C_GREEN" "$C_RESET"
    read -r choice
    if [ -z "$choice" ] || [ "$choice" = "0" ]; then
        return
    fi

    if [ "$choice" = "A" ] || [ "$choice" = "a" ]; then
        for p in "${pkgs[@]}"; do
            is_valid_pkg "$p" || continue
            am force-stop "$p" >/dev/null 2>&1
            rm -rf "/data/data/$p/app_webview" "/data/data/$p/shared_prefs" 2>/dev/null
        done
        ok_msg "Đã logout toàn bộ."
    elif [[ "$choice" =~ ^[0-9]+$ ]]; then
        local idx=$((choice - 1))
        pkg="${pkgs[$idx]:-}"
        if [ -n "$pkg" ] && is_valid_pkg "$pkg"; then
            am force-stop "$pkg" >/dev/null 2>&1
            rm -rf "/data/data/$pkg/app_webview" "/data/data/$pkg/shared_prefs" 2>/dev/null
            ok_msg "Đã logout $pkg."
        else
            warn_msg "Số không hợp lệ."
        fi
    elif is_valid_pkg "$choice"; then
        am force-stop "$choice" >/dev/null 2>&1
        rm -rf "/data/data/$choice/app_webview" "/data/data/$choice/shared_prefs" 2>/dev/null
        ok_msg "Đã logout $choice."
    else
        warn_msg "Lựa chọn không hợp lệ."
    fi
    pause_key
}

# ------------------------------------------------------------
# Export cookie
# ------------------------------------------------------------
export_cookies() {
    clear
    printf '%s┌── [ EXPORT COOKIES ] ────────────────────┐%s\n' "$C_CYAN" "$C_RESET"
    warn_msg "File export chứa cookie đăng nhập. Không chia sẻ!"
    local pkg db cval check uname count=0
    if ! : > "$EXPORT_FILE" 2>/dev/null; then
        warn_msg "Không ghi được file export: $EXPORT_FILE"
        pause_key
        return
    fi
    chmod 600 "$EXPORT_FILE" 2>/dev/null

    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        db="/data/data/$pkg/app_webview/Default/Cookies"
        [ -f "$db" ] || db="/data/data/$pkg/app_webview/Cookies"
        cval=""
        if [ -f "$db" ]; then
            cval="$(sqlite3 -readonly "$db" "SELECT value FROM cookies WHERE name='.ROBLOSECURITY' LIMIT 1;" 2>/dev/null)"
        fi
        if [ -z "$cval" ]; then
            printf ' %s[-]%s %s (trống)\n' "$C_GRAY" "$C_RESET" "$pkg"
            continue
        fi
        check="$(verify_cookie "$cval")"
        uname="$(printf '%s' "$check" | cut -d'|' -f3)"
        [ -z "$uname" ] && uname="Invalid_Session"
        printf '[%s] [%s]: %s\n' "$pkg" "$uname" "$cval" >> "$EXPORT_FILE"
        printf ' %s[✓]%s %s %s(%s)%s\n' "$C_GREEN" "$C_RESET" "$pkg" "$C_YELLOW" "$uname" "$C_RESET"
        count=$((count + 1))
    done < <(get_all_installed_roblox)

    printf '%s└──────────────────────────────────────────┘%s\n' "$C_CYAN" "$C_RESET"
    ok_msg "Đã lưu $count cookie vào $EXPORT_FILE"
    pause_key
}

# ------------------------------------------------------------
# Auto rejoin
# ------------------------------------------------------------
countdown_rejoin() {
    local pkg="$1" reason="$2" delay="$3" cd
    for ((cd = delay; cd > 0; cd--)); do
        [ "$AUTO_RUNNING" -eq 1 ] || return 1
        printf '\033[H'
        printf '%s┌── [ TỰ ĐỘNG REJOIN ] ───────────────────┐%s\n' "$C_CYAN" "$C_RESET"
        printf '│ %-38s │\n' "$reason"
        printf '│ %-20s còn %2ds...       │\n' "${pkg:0:20}" "$cd"
        printf '│ %s[Ctrl+C] dừng auto rejoin%s               │\n' "$C_WHITE" "$C_RESET"
        printf '%s└──────────────────────────────────────────┘%s\n' "$C_CYAN" "$C_RESET"
        sleep 1
    done
    return 0
}

rejoin_pkg() {
    local pkg="$1" link="$2" reason="$3" delay="$4"
    if [ "$delay" -gt 0 ]; then
        countdown_rejoin "$pkg" "$reason" "$delay" || return 1
    fi
    [ "$AUTO_RUNNING" -eq 1 ] || return 1
    launch_package "$pkg" "$link" || return 1
    CYCLE_START[$pkg]="$(date +%s)"
    LAST_REJOIN[$pkg]="$(date +%s)"
    return 0
}

recent_disconnect() {
    local pid="$1" out="${LOGCAT_SNAPSHOT:-}"
    [ -n "$out" ] || return 1
    printf '%s' "$out" \
        | grep -E "(^|[[:space:]])${pid}([[:space:]]|$)" \
        | grep -qiE 'Game ended|Disconnecting from server|Connection lost|Lost connection|Disconnected from|ErrorPrompt|kicked|leaveGame|User requested leave'
}

start_auto_rejoin() {
    clear
    if [ ! -s "$CONF_FILE" ]; then
        warn_msg "Chưa cấu hình package. Vào mục 2 hoặc 4 trước."
        pause_key
        return
    fi

    local -a PKGS=()
    local -a LINKS=()
    local line pkg link
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        case "$line" in *=*) ;; *) continue ;; esac
        pkg="${line%%=*}"
        link="${line#*=}"
        pkg="${pkg%$'\r'}"
        link="${link%$'\r'}"
        is_valid_pkg "$pkg" || { warn_msg "Bỏ qua package lỗi: $pkg"; continue; }
        [ -d "/data/data/$pkg" ] || { warn_msg "Bỏ qua (chưa cài): $pkg"; continue; }
        PKGS+=("$pkg")
        LINKS+=("$link")
    done < "$CONF_FILE"

    if [ "${#PKGS[@]}" -eq 0 ]; then
        warn_msg "Không có package hợp lệ."
        pause_key
        return
    fi

    local reset_in delay_in max_runtime interval
    printf '%sChu kỳ reset (phút, Enter=30, 0=tắt): %s' "$C_WHITE" "$C_RESET"
    read -r reset_in
    reset_in="${reset_in:-30}"
    [[ "$reset_in" =~ ^[0-9]+$ ]] || reset_in=30
    max_runtime=$((reset_in * 60))

    printf '%sDelay rejoin (giây, Enter=15): %s' "$C_WHITE" "$C_RESET"
    read -r delay_in
    delay_in="${delay_in:-15}"
    [[ "$delay_in" =~ ^[0-9]+$ ]] || delay_in=15

    interval="$(conf_get "$DISCORD_CONF" INTERVAL 2>/dev/null)"
    interval="${interval:-15}"
    [[ "$interval" =~ ^[0-9]+$ ]] || interval=15

    declare -gA CYCLE_START=()
    declare -gA LAST_REJOIN=()
    declare -gA CRASH_COUNT=()

    AUTO_RUNNING=1
    IN_AUTO=1

    local now
    for i in "${!PKGS[@]}"; do
        [ "$AUTO_RUNNING" -eq 1 ] || break
        pkg="${PKGS[$i]}"
        link="${LINKS[$i]}"
        now="$(date +%s)"
        CYCLE_START[$pkg]="$now"
        LAST_REJOIN[$pkg]="0"
        CRASH_COUNT[$pkg]="0"
        printf ' %s→ Đang mở %s...%s\n' "$C_YELLOW" "$pkg" "$C_RESET"
        launch_package "$pkg" "$link"
    done

    if [ "$AUTO_RUNNING" -eq 1 ]; then
        if [ "$HAS_TPUT" -eq 1 ]; then
            tput civis 2>/dev/null || printf '\033[?25l'
        else
            printf '\033[?25l'
        fi
    fi

    local w
    for ((w = 15; w > 0; w--)); do
        [ "$AUTO_RUNNING" -eq 1 ] || break
        printf '\033[H'
        printf '%s┌── [ ROBLOX AUTO-REJOIN ] ────────────────┐%s\n' "$C_CYAN" "$C_RESET"
        printf '│ Đang khởi động & vào game (%2ds)...      │\n' "$w"
        printf '%s└──────────────────────────────────────────┘%s\n' "$C_CYAN" "$C_RESET"
        sleep 1
    done

    local webhook_url
    webhook_url="$(get_webhook_url)"
    if [ -n "$webhook_url" ] && [ "$interval" -gt 0 ] && [ "$AUTO_RUNNING" -eq 1 ]; then
        (
            while sleep "$((interval * 60))"; do
                send_webhook "Ivy TUN Uptime" \
                    "Auto rejoin đang chạy.
- Thiết bị: Android
- Thời gian: $(date '+%H:%M:%S %d/%m/%Y')" 5814783 >/dev/null 2>&1
            done
        ) &
        UPTIME_PID=$!
    fi

    local pid state state_text age since_rejoin remain remain_text
    while [ "$AUTO_RUNNING" -eq 1 ]; do
        printf '\033[H'
        printf '%s┌── [ ROBLOX IN-GAME MONITOR ] ────────────┐%s\n' "$C_CYAN" "$C_RESET"
        now="$(date +%s)"
        LOGCAT_SNAPSHOT="$(logcat -d -t 800 2>/dev/null)"
        if [ -z "$LOGCAT_SNAPSHOT" ]; then
            LOGCAT_SNAPSHOT="$(logcat -d 2>/dev/null | tail -n 800)"
        fi

        for i in "${!PKGS[@]}"; do
            pkg="${PKGS[$i]}"
            link="${LINKS[$i]}"
            [ "$AUTO_RUNNING" -eq 1 ] || break

            pid="$(pidof "$pkg" 2>/dev/null | awk '{print $1}')"
            age=$((now - ${CYCLE_START[$pkg]:-$now}))
            since_rejoin=$((now - ${LAST_REJOIN[$pkg]:-0}))
            state="OK"
            state_text="TRONG GAME"

            if [ "$age" -lt 15 ] || [ "$since_rejoin" -lt 30 ]; then
                state="WAIT"
                state_text="ĐANG CHỜ"
            elif [ -z "$pid" ]; then
                state="CRASHED"
                state_text="VĂNG APP"
            elif recent_disconnect "$pid"; then
                state="DISCONNECTED"
                state_text="MẤT KẾT NỐI"
            fi

            if [ "$max_runtime" -gt 0 ] && [ "$age" -ge "$max_runtime" ]; then
                state="RESET"
                state_text="HẾT CHU KỲ"
            fi

            if [ "$state" = "CRASHED" ] || [ "$state" = "DISCONNECTED" ]; then
                CRASH_COUNT[$pkg]=$(( ${CRASH_COUNT[$pkg]:-0} + 1 ))
                if rejoin_pkg "$pkg" "$link" "$state_text: ${pkg:0:18}" "$delay_in"; then
                    state_text="ĐÃ REJOIN"
                fi
            elif [ "$state" = "RESET" ]; then
                if rejoin_pkg "$pkg" "$link" "Hết chu kỳ: ${pkg:0:18}" 0; then
                    state_text="ĐÃ RESET"
                fi
            fi

            now="$(date +%s)"
            age=$((now - ${CYCLE_START[$pkg]:-$now}))
            if [ "$max_runtime" -gt 0 ]; then
                remain=$((max_runtime - age))
                [ "$remain" -lt 0 ] && remain=0
                remain_text="$(printf '%02d:%02d' $((remain / 60)) $((remain % 60)))"
            else
                remain_text="OFF"
            fi

            if [ "$state" = "OK" ] && [ -n "$pid" ]; then
                state_text="TRONG GAME (PID $pid)"
            fi

            printf '│ %s%-20s%s Rejoin: %-2d          │\n' \
                "$C_YELLOW" "${pkg:0:20}" "$C_RESET" "${CRASH_COUNT[$pkg]:-0}"
            printf '│ TT: %-34s │\n' "$state_text"
            printf '│ Reset sau: %-27s │\n' "$remain_text"
            printf '%s├──────────────────────────────────────────┤%s\n' "$C_CYAN" "$C_RESET"
        done

        printf '%s└──────────────────────────────────────────┘%s\n' "$C_CYAN" "$C_RESET"
        printf ' %s[Ctrl+C] quay lại menu%s\n' "$C_GRAY" "$C_RESET"
        sleep 2
    done

    stop_uptime
    IN_AUTO=0
    AUTO_RUNNING=0
    if [ "$HAS_TPUT" -eq 1 ]; then
        tput cnorm 2>/dev/null || printf '\033[?25h'
    else
        printf '\033[?25h'
    fi
    printf '\n%sĐã dừng auto rejoin.%s\n' "$C_GREEN" "$C_RESET"
    pause_key
}

# ------------------------------------------------------------
# Menu chính
# ------------------------------------------------------------
main_menu() {
    while true; do
        clear
        local pkg_count webhook_state
        pkg_count="$(grep -c '=' "$CONF_FILE" 2>/dev/null || true)"
        pkg_count="${pkg_count:-0}"
        if [ -n "$(get_webhook_url)" ]; then
            webhook_state="${C_GREEN}đã cấu hình${C_RESET}"
        else
            webhook_state="${C_RED}chưa cấu hình${C_RESET}"
        fi

        printf '%s⚡ Ivy TUN v%s%s\n' "$C_CYAN" "$SCRIPT_VERSION" "$C_RESET"
        printf ' %sConfig:%s %s\n' "$C_GRAY" "$C_RESET" "$CONF_DIR"
        printf ' %sPackages:%s %s | %sWebhook:%s %s\n\n' "$C_GRAY" "$C_RESET" "$pkg_count" "$C_GRAY" "$C_RESET" "$webhook_state"

        printf '%s┌── Auto Rejoin ────────────────────────────┐%s\n' "$C_CYAN" "$C_RESET"
        printf '│ %s1%s  Start auto rejoin + uptime            │\n' "$C_YELLOW" "$C_RESET"
        printf '%s├── Server Setup ───────────────────────────┤%s\n' "$C_CYAN" "$C_RESET"
        printf '│ %s2%s  Select package & assign link          │\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s3%s  List selected packages                │\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s4%s  Auto-select all with one link         │\n' "$C_YELLOW" "$C_RESET"
        printf '%s├── Tabs ───────────────────────────────────┤%s\n' "$C_CYAN" "$C_RESET"
        printf '│ %s5%s  Open all Roblox tabs                  │\n' "$C_YELLOW" "$C_RESET"
        printf '%s├── Account & Profiles ─────────────────────┤%s\n' "$C_CYAN" "$C_RESET"
        printf '│ %s6%s  Login via cookie (verify API)         │\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s7%s  Quản lý acc theo profile              │\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s8%s  Logout Roblox                         │\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s9%s  Export cookies                        │\n' "$C_YELLOW" "$C_RESET"
        printf '%s├── Discord & System ───────────────────────┤%s\n' "$C_CYAN" "$C_RESET"
        printf '│ %s10%s Cấu hình Discord webhook/uptime       │\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s11%s Xem toàn bộ package quét được         │\n' "$C_YELLOW" "$C_RESET"
        printf '│ %s12%s Thoát                                │\n' "$C_RED" "$C_RESET"
        printf '%s└───────────────────────────────────────────┘%s\n\n' "$C_CYAN" "$C_RESET"

        printf '%sLựa chọn: %s' "$C_MAGENTA" "$C_RESET"
        read -r choice

        case "$choice" in
            1) start_auto_rejoin ;;
            2) select_packages_assign_link ;;
            3) list_selected_packages ;;
            4) auto_select_all_one_link ;;
            5) open_all_tabs ;;
            6) login_via_cookie ;;
            7) manage_account_profiles ;;
            8) logout_roblox ;;
            9) export_cookies ;;
            10) manage_discord_webhook ;;
            11)
                clear
                printf '%sToàn bộ package quét được:%s\n\n' "$C_CYAN" "$C_RESET"
                get_all_installed_roblox | while IFS= read -r p; do
                    printf '  %s•%s %s\n' "$C_GREEN" "$C_RESET" "$p"
                done
                pause_key
                ;;
            12|0) cleanup ;;
            *) sleep 1 ;;
        esac
    done
}

main_menu
