#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Ivy TUN v2.4.1
# Optimized multi-account Roblox helper for rooted Android + Termux.
#
# CHỈ DÙNG VỚI THIẾT BỊ VÀ TÀI KHOẢN CỦA BẠN.
# Cookie .ROBLOSECURITY là chìa khóa đăng nhập: không chia sẻ file
# profiles.conf, cookie.txt hoặc file export cho bất kỳ ai.
# ============================================================

set -o pipefail
umask 077

APP_NAME="Ivy TUN"
SCRIPT_VERSION="2.4.1"

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
SETTINGS_FILE="$CONF_DIR/settings.conf"
# pidfile đặt ở /data/local/tmp: không bị ảnh hưởng bởi /sdcard chưa mount lúc boot
SUP_PID_FILE="/data/local/tmp/ivy-tun-supervisor.pid"
BOOT_DIR="$TERMUX_HOME/.termux/boot"
BOOT_STUB="$BOOT_DIR/ivy-tun-boot.sh"

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

# Đường dẫn tuyệt đối của chính script (dùng cho supervisor / Termux:Boot)
SELF_PATH="$0"
if command -v realpath >/dev/null 2>&1; then
    SELF_PATH="$(realpath "$0" 2>/dev/null || printf '%s' "$0")"
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

for _f in "$CONF_FILE" "$PROFILES_FILE" "$DISCORD_CONF" "$COOKIE_INPUT_FILE" "$SETTINGS_FILE"; do
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
HAS_WAKE_LOCK=1
command -v termux-wake-lock >/dev/null 2>&1 || HAS_WAKE_LOCK=0
HAS_UIAUTOMATOR=1
command -v uiautomator >/dev/null 2>&1 || HAS_UIAUTOMATOR=0
HAS_DUMPSYS=1
command -v dumpsys >/dev/null 2>&1 || HAS_DUMPSYS=0
UI_DUMP_FILE="/data/local/tmp/ivy-tun-ui.xml"

# ------------------------------------------------------------
# Biến toàn cục cho auto rejoin / webhook uptime
# ------------------------------------------------------------
UPTIME_PID=""
AUTO_RUNNING=0
IN_AUTO=0
LOGCAT_SNAPSHOT=""
WAKE_LOCK_HELD=0
HEADLESS=0          # 1 = chế độ --auto: không giao diện, không hỏi gì
SUP_STOP=0
SUP_CHILD=""

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
    printf '%s[OK] %s%s\n' "$C_GREEN" "$*" "$C_RESET"
    log_line "OK $*"
}

warn_msg() {
    printf '%s[!] %s%s\n' "$C_RED" "$*" "$C_RESET" >&2
    log_line "WARN $*"
}

pause_key() {
    [ "$HEADLESS" -eq 1 ] && return 0
    printf '\n%sBấm Enter để tiếp tục...%s' "$C_WHITE" "$C_RESET"
    read -r _
}

# ------------------------------------------------------------
# UI helpers
# ------------------------------------------------------------
UI_WIDTH=58

ui_repeat() {
    local ch="$1" n="$2" out
    printf -v out '%*s' "$n" ''
    printf '%s' "${out// /$ch}"
}

ui_top() {
    printf '%s╭%s%s\n' "$C_CYAN" "$(ui_repeat '─' $((UI_WIDTH - 1)))" "$C_RESET"
}

ui_mid() {
    printf '%s├%s%s\n' "$C_CYAN" "$(ui_repeat '─' $((UI_WIDTH - 1)))" "$C_RESET"
}

ui_bottom() {
    printf '%s╰%s%s\n' "$C_CYAN" "$(ui_repeat '─' $((UI_WIDTH - 1)))" "$C_RESET"
}

ui_title() {
    printf '%s│%s  %s%s%s\n' "$C_CYAN" "$C_RESET" "$C_BOLD$C_WHITE" "$1" "$C_RESET"
}

ui_section() {
    local title="$1"
    local n=$((UI_WIDTH - 4 - ${#title}))
    [ "$n" -lt 2 ] && n=2
    printf '%s├─ %s%s%s %s%s%s\n' \
        "$C_CYAN" "$C_BOLD$C_WHITE" "$title" "$C_RESET" \
        "$C_CYAN" "$(ui_repeat '─' "$n")" "$C_RESET"
}

ui_kv() {
    printf '%s│%s  %s%-11s%s %s\n' \
        "$C_CYAN" "$C_RESET" "$C_GRAY" "$1" "$C_RESET" "$2"
}

ui_kv2() {
    printf '%s│%s  %s%-11s%s %-20s %s%-9s%s %s\n' \
        "$C_CYAN" "$C_RESET" "$C_GRAY" "$1" "$C_RESET" "$2" \
        "$C_GRAY" "$3" "$C_RESET" "$4"
}

ui_line() {
    printf '%s│%s  %s\n' "$C_CYAN" "$C_RESET" "$1"
}

ui_note() {
    printf '%s│%s  %s%s%s\n' "$C_CYAN" "$C_RESET" "$C_GRAY" "$1" "$C_RESET"
}

ui_item() {
    printf '%s│%s  %s%2s%s  %s\n' \
        "$C_CYAN" "$C_RESET" "$C_YELLOW" "$1" "$C_RESET" "$2"
}

ui_prompt() {
    printf '\n%s>%s %s%s%s' "$C_MAGENTA" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
}

# Giữ CPU/Termux không ngủ khi auto-rejoin chạy nền.
acquire_wake_lock() {
    [ "$HAS_WAKE_LOCK" -eq 1 ] || return 0
    [ "$WAKE_LOCK_HELD" -eq 1 ] && return 0
    if termux-wake-lock >/dev/null 2>&1; then
        WAKE_LOCK_HELD=1
        log_line "INFO wake-lock acquired"
    fi
}

release_wake_lock() {
    [ "$WAKE_LOCK_HELD" -eq 1 ] || return 0
    termux-wake-unlock >/dev/null 2>&1 || true
    WAKE_LOCK_HELD=0
    log_line "INFO wake-lock released"
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
# Tất cả app người dùng đã cài, gồm cả app ở user khác / app clone.
# App Roblox-like được đưa lên trước để dễ chọn.
get_all_installed_packages() {
    local all rbx rest
    all="$(
        {
            pm list packages -3 2>/dev/null
            pm list packages --user all -3 2>/dev/null
            pm list packages --user 0 -3 2>/dev/null
            pm list packages 2>/dev/null | grep -iE 'roblox|delta|deltb|fluxus|hydrogen|codex|arceus|rejoin|rbx'
            pm list packages --user all 2>/dev/null | grep -iE 'roblox|delta|deltb|fluxus|hydrogen|codex|arceus|rejoin|rbx'
        } | sed 's/^package://' | tr -d '\r' | sed '/^[[:space:]]*$/d' | sort -u
    )"
    [ -z "$all" ] && return 0

    rbx="$(printf '%s\n' "$all" | grep -iE 'roblox|delta|deltb|fluxus|hydrogen|codex|arceus|rejoin|rbx' || true)"
    rest="$(printf '%s\n' "$all" | grep -ivE 'roblox|delta|deltb|fluxus|hydrogen|codex|arceus|rejoin|rbx' || true)"
    [ -n "$rbx" ] && printf '%s\n' "$rbx"
    [ -n "$rest" ] && printf '%s\n' "$rest"
}

# Chỉ các package Roblox-like, dùng cho auto-rejoin/cookie/export.
get_all_installed_roblox() {
    get_all_installed_packages \
        | grep -iE 'roblox|delta|deltb|fluxus|hydrogen|codex|arceus|rejoin|rbx' || true
}

# In danh sách có số thứ tự, trả về package được chọn qua stdout
select_package() {
    local prompt="${1:-Chọn package}"
    local -a pkgs=()
    local i sel

    mapfile -t pkgs < <(get_all_installed_packages)
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

# Chọn nhiều package: nhập số cách nhau bằng dấu cách, 0 để xác nhận.
SELECTED_PKGS=()

select_multiple_packages() {
    local -a all=() tokens=()
    local input token pkg idx p exists confirm
    SELECTED_PKGS=()
    mapfile -t all < <(get_all_installed_packages)
    if [ "${#all[@]}" -eq 0 ]; then
        warn_msg "Không tìm thấy package nào."
        return 1
    fi

    ui_top
    ui_section "CHỌN PACKAGE"
    for idx in "${!all[@]}"; do
        ui_item "$((idx + 1))" "${all[$idx]}"
    done
    ui_note "Nhập số package, cách nhau bằng dấu cách. 0 = xác nhận."
    ui_bottom

    while true; do
        printf '\n%sPackage (0=xác nhận): %s' "$C_GREEN" "$C_RESET"
        read -r input || return 1
        input="${input//$'\r'/}"
        confirm=0
        tokens=()
        read -r -a tokens <<< "$(printf '%s' "$input" | tr ',' ' ')"
        for token in "${tokens[@]}"; do
            if [ "$token" = "0" ]; then
                confirm=1
                break
            fi

            if [[ "$token" =~ ^[0-9]+$ ]]; then
                idx=$((token - 1))
                if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#all[@]}" ]; then
                    warn_msg "Số $token không hợp lệ."
                    continue
                fi
                pkg="${all[$idx]}"
            elif is_valid_pkg "$token"; then
                pkg="$token"
            else
                warn_msg "Package không hợp lệ: $token"
                continue
            fi

            exists=0
            for p in "${SELECTED_PKGS[@]}"; do
                if [ "$p" = "$pkg" ]; then
                    exists=1
                    break
                fi
            done
            if [ "$exists" -eq 1 ]; then
                printf ' %s-%s %s (đã chọn)\n' "$C_GRAY" "$C_RESET" "$pkg"
            else
                SELECTED_PKGS+=("$pkg")
                printf ' %s[OK]%s Đã thêm: %s\n' "$C_GREEN" "$C_RESET" "$pkg"
            fi
        done

        if [ "$confirm" -eq 1 ]; then
            if [ "${#SELECTED_PKGS[@]}" -eq 0 ]; then
                warn_msg "Chưa chọn package nào."
                continue
            fi
            break
        fi
        if [ -z "$input" ]; then
            warn_msg "Nhập số package hoặc 0 để xác nhận."
        fi
    done

    printf '\n%sĐã chọn %d package:%s\n' "$C_CYAN" "${#SELECTED_PKGS[@]}" "$C_RESET"
    for pkg in "${SELECTED_PKGS[@]}"; do
        printf '  %s-%s %s\n' "$C_GREEN" "$C_RESET" "$pkg"
    done
    return 0
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
    footer_j="$(json_escape "$APP_NAME | $now_str")"

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
    release_wake_lock
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

        ui_top
        ui_title "DISCORD WEBHOOK & UPTIME"
        if [ -n "$url" ]; then
            shown="$(mask_secret "$url")"
            ui_kv "Webhook" "$shown"
        else
            ui_kv "Webhook" "chưa cài đặt"
        fi
        ui_kv "Uptime" "$interval phút"
        ui_note "Gửi uptime khi auto rejoin đang chạy."
        ui_section "CHỨC NĂNG"
        ui_item 1 "Nhập URL Webhook mới"
        ui_item 2 "Đổi chu kỳ uptime (phút)"
        ui_item 3 "Test gửi ảnh + thông báo"
        ui_item 4 "Xóa cấu hình webhook"
        ui_item 0 "Quay lại"
        ui_bottom

        ui_prompt "Lựa chọn: "
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
                    if send_webhook "$APP_NAME Test Webhook" \
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
        ui_top
        ui_section "QUẢN LÝ ACC THEO PROFILE"
        if [ ! -s "$PROFILES_FILE" ]; then
            ui_note "Chưa có profile nào."
        else
            local idx=0 line
            while IFS= read -r line || [ -n "$line" ]; do
                [ -z "$line" ] && continue
                parse_profile_line "$line" || continue
                idx=$((idx + 1))
                ui_line "${C_YELLOW}[$idx]${C_RESET} ${C_CYAN}${P_PKG}${C_RESET} (${P_UNAME:-Unknown} - ID: ${P_UID:-N/A})"
                ui_note "Place: ${P_PLACE:0:20} | Cookie: $(mask_secret "$P_COOKIE")"
            done < "$PROFILES_FILE"
        fi
        ui_section "CHỨC NĂNG"
        ui_item 1 "Thêm profile (verify cookie)"
        ui_item 2 "Đồng bộ profile -> packages.conf"
        ui_item 3 "Nạp cookie từ tất cả profile"
        ui_item 4 "Xóa một profile"
        ui_item 5 "Xóa toàn bộ profile"
        ui_item 0 "Quay lại"
        ui_bottom

        ui_prompt "Lựa chọn: "
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
    clear
    local pkg link
    select_multiple_packages || return
    printf '\n%sNhập Place ID/Link riêng cho từng package đã chọn.%s\n' "$C_CYAN" "$C_RESET"

    for pkg in "${SELECTED_PKGS[@]}"; do
        while true; do
            printf '%sPlace ID/Link cho %s%s%s (0=bỏ qua): %s' "$C_WHITE" "$C_YELLOW" "$pkg" "$C_WHITE" "$C_RESET"
            read -r link
            link="${link//$'\r'/}"
            if [ -z "$link" ]; then
                warn_msg "Link trống."
                continue
            fi
            [ "$link" = "0" ] && break
            if conf_set "$CONF_FILE" "$pkg" "$link"; then
                ok_msg "Đã lưu $pkg"
            else
                warn_msg "Không lưu được $pkg"
            fi
            break
        done
    done
    pause_key
}

list_selected_packages() {
    clear
    ui_top
    ui_section "PACKAGES ĐÃ CẤU HÌNH"
    if [ ! -s "$CONF_FILE" ]; then
        ui_note "Chưa có package nào."
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
            ui_line "${C_YELLOW}$idx.${C_RESET} $pkg"
            ui_note "Link: ${link:0:50}"
        done < "$CONF_FILE"
    fi
    ui_note "File: $CONF_FILE"
    ui_bottom
    pause_key
}

auto_select_all_one_link() {
    clear
    ui_top
    ui_section "GÁN TẤT CẢ CHUNG 1 LINK"
    local -a pkgs=()
    local p link
    mapfile -t pkgs < <(get_all_installed_roblox)
    if [ "${#pkgs[@]}" -eq 0 ]; then
        ui_line "${C_RED}[!] Không có package.${C_RESET}"
        ui_bottom
        log_line "WARN Không có package."
        pause_key
        return
    fi
    for p in "${pkgs[@]}"; do
        ui_line "${C_GRAY}-${C_RESET} $p"
    done
    ui_bottom

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
    ui_top
    ui_section "MỞ TOÀN BỘ TABS ROBLOX"
    local line pkg link
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        case "$line" in *=*) ;; *) continue ;; esac
        pkg="${line%%=*}"
        link="${line#*=}"
        pkg="${pkg%$'\r'}"
        link="${link%$'\r'}"
        is_valid_pkg "$pkg" || continue
        ui_line "${C_YELLOW}->${C_RESET} $pkg"
        open_package_tab "$pkg" "$link"
        sleep 5
    done < "$CONF_FILE"
    ui_bottom
    ok_msg "Đã mở xong các tab."
    pause_key
}

# ------------------------------------------------------------
# Login cookie
# ------------------------------------------------------------
login_via_cookie() {
    clear
    ui_top
    ui_section "LOGIN VIA COOKIE"
    ui_item 1 "Nạp từ file cookie.txt (theo thứ tự package)"
    ui_item 2 "Chọn package và nhập cookie"
    ui_item 0 "Quay lại"
    ui_note "File: $COOKIE_INPUT_FILE"
    ui_bottom
    ui_prompt "Chọn: "
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
                printf ' %s-> Dòng %d: %s%s\n' "$C_YELLOW" "$idx" "$pkg" "$C_RESET"
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
    warn_msg "File export chứa cookie đăng nhập. Không chia sẻ!"
    ui_top
    ui_section "EXPORT COOKIES"
    local pkg db cval check uname count=0
    if ! : > "$EXPORT_FILE" 2>/dev/null; then
        ui_line "${C_RED}[!] Không ghi được file export: $EXPORT_FILE${C_RESET}"
        ui_bottom
        log_line "WARN Không ghi được file export: $EXPORT_FILE"
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
            ui_line "${C_GRAY}[-]${C_RESET} $pkg (trống)"
            continue
        fi
        check="$(verify_cookie "$cval")"
        uname="$(printf '%s' "$check" | cut -d'|' -f3)"
        [ -z "$uname" ] && uname="Invalid_Session"
        printf '[%s] [%s]: %s\n' "$pkg" "$uname" "$cval" >> "$EXPORT_FILE"
        ui_line "${C_GREEN}[OK]${C_RESET} $pkg ${C_YELLOW}($uname)${C_RESET}"
        count=$((count + 1))
    done < <(get_all_installed_roblox)

    ui_bottom
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
        ui_top
        ui_section "TỰ ĐỘNG REJOIN"
        ui_line "$reason"
        ui_line "${C_YELLOW}${pkg:0:20}${C_RESET} còn ${C_BOLD}${cd}s${C_RESET}..."
        ui_note "[Ctrl+C] dừng auto rejoin"
        ui_bottom
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
    log_line "REJOIN $pkg | $reason"
    launch_package "$pkg" "$link" || return 1
    CYCLE_START[$pkg]="$(date +%s)"
    LAST_REJOIN[$pkg]="$(date +%s)"
    GAME_SEEN[$pkg]=0
    HOME_MISS[$pkg]=0
    HOME_LEFT[$pkg]=0
    return 0
}

package_logcat() {
    local pids="$1" p out=""
    for p in $pids; do
        [[ "$p" =~ ^[0-9]+$ ]] || continue
        out+="$(logcat -d --pid="$p" -t 500 2>/dev/null)"$'\n'
    done
    printf '%s' "$out"
}

recent_disconnect() {
    local pids="$1" out="${2:-${LOGCAT_SNAPSHOT:-}}" re="" p
    [ -n "$out" ] || return 1
    for p in $pids; do
        [[ "$p" =~ ^[0-9]+$ ]] || continue
        re="${re:+$re|}$p"
    done
    [ -n "$re" ] || return 1
    printf '%s' "$out" \
        | grep -E "(^|[[:space:]])(${re})([[:space:]]|$)" \
        | grep -qiE 'Game ended|Game left|Left game|Left the game|GameLeave|LeaveGame|leaveGame|Leaving game|Leaving experience|Leave experience|GameExit|Game exit|Exit game|GameEnd|User requested leave|User left|Experience.*(ended|left|closed)|Disconnected|Disconnecting from server|Connection lost|Lost connection|Connection closed|Connection refused|Failed to connect|Unable to connect|Network.*(lost|error|disconnect)|Socket.*(closed|lost)|kicked|ErrorPrompt|Error.*(connection|network|disconnect)|Reconnect|Rejoining'
}

get_foreground_package() {
    [ "$HAS_DUMPSYS" -eq 1 ] || return 0
    local out
    out="$(dumpsys window 2>/dev/null | grep -m1 'mCurrentFocus' || true)"
    case "$out" in
        */*) ;;
        *)
            out="$(dumpsys activity activities 2>/dev/null | grep -m1 'mResumedActivity' || true)"
            ;;
    esac
    printf '%s' "$out" \
        | grep -oE '[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+/[A-Za-z0-9_.$]+' \
        | head -n 1 \
        | cut -d/ -f1
}

# 0 = màn hình Home/Leave App, 1 = không phải Home, 2 = không đọc được UI.
ui_is_home_screen() {
    [ "$HAS_UIAUTOMATOR" -eq 1 ] || return 2
    rm -f "$UI_DUMP_FILE" 2>/dev/null
    if ! uiautomator dump "$UI_DUMP_FILE" >/dev/null 2>&1; then
        rm -f "$UI_DUMP_FILE" 2>/dev/null
        return 2
    fi
    [ -s "$UI_DUMP_FILE" ] || {
        rm -f "$UI_DUMP_FILE" 2>/dev/null
        return 2
    }

    # Hộp thoại Leave App là dấu hiệu chắc chắn, chỉ cần 1 marker.
    if grep -qiE '(text|content-desc)="(Do you want to leave the app\?|LEAVE APP|Bạn có muốn rời ứng dụng\?)"' "$UI_DUMP_FILE"; then
        rm -f "$UI_DUMP_FILE" 2>/dev/null
        return 0
    fi

    # Home có nhiều tab; cần ít nhất 2 marker để tránh nhận nhầm UI trong game.
    local count
    count="$(grep -oiE '(text|content-desc)="(Home|For you|Charts|Build|Search|More|Trang chủ|Bảng xếp hạng|Tạo|Tìm kiếm|Thêm)"' "$UI_DUMP_FILE" 2>/dev/null | sort -u | wc -l)"
    rm -f "$UI_DUMP_FILE" 2>/dev/null
    count="${count//[^0-9]/}"
    [ "${count:-0}" -ge 2 ]
}

start_auto_rejoin() {
    if [ "$HEADLESS" -eq 0 ]; then
        if sup_pid_alive; then
            clear
            warn_msg "Đang có chế độ chạy nền (PID $(cat "$SUP_PID_FILE" 2>/dev/null)). Dừng nó ở mục 12 trước, kẻo hai bên đá nhau."
            pause_key
            return 1
        fi
        clear
    fi
    if [ ! -s "$CONF_FILE" ]; then
        warn_msg "Chưa cấu hình package. Vào mục 2 hoặc 4 trước."
        pause_key
        return 3
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
        return 3
    fi

    acquire_wake_lock
    local reset_in delay_in max_runtime interval launch_gap
    if [ "$HEADLESS" -eq 1 ]; then
        # Chế độ nền: dùng giá trị đã lưu (lần cuối bạn nhập ở menu).
        reset_in="$(conf_get "$SETTINGS_FILE" RESET_MIN 2>/dev/null)"
        delay_in="$(conf_get "$SETTINGS_FILE" REJOIN_DELAY 2>/dev/null)"
        launch_gap="$(conf_get "$SETTINGS_FILE" LAUNCH_GAP 2>/dev/null)"
    else
        printf '%sChu kỳ reset (phút, Enter=30, 0=tắt): %s' "$C_WHITE" "$C_RESET"
        read -r reset_in
        printf '%sDelay rejoin (giây, Enter=15): %s' "$C_WHITE" "$C_RESET"
        read -r delay_in
    fi
    reset_in="${reset_in:-30}"
    [[ "$reset_in" =~ ^[0-9]+$ ]] || reset_in=30
    delay_in="${delay_in:-15}"
    [[ "$delay_in" =~ ^[0-9]+$ ]] || delay_in=15
    launch_gap="${launch_gap:-5}"
    [[ "$launch_gap" =~ ^[0-9]+$ ]] || launch_gap=5
    max_runtime=$((reset_in * 60))
    if [ "$HEADLESS" -eq 0 ]; then
        # Lưu lại để lần tự chạy sau khi boot dùng đúng giá trị này.
        conf_set "$SETTINGS_FILE" RESET_MIN "$reset_in"
        conf_set "$SETTINGS_FILE" REJOIN_DELAY "$delay_in"
    fi
    log_line "AUTO start: ${#PKGS[@]} package, reset=${reset_in}m, delay=${delay_in}s, headless=$HEADLESS, resume=${IVY_RESUME:-0}"

    interval="$(conf_get "$DISCORD_CONF" INTERVAL 2>/dev/null)"
    interval="${interval:-15}"
    [[ "$interval" =~ ^[0-9]+$ ]] || interval=15

    declare -gA CYCLE_START=()
    declare -gA LAST_REJOIN=()
    declare -gA CRASH_COUNT=()
    declare -gA GAME_SEEN=()
    declare -gA HOME_MISS=()
    declare -gA HOME_LEFT=()

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
        GAME_SEEN[$pkg]=0
        HOME_MISS[$pkg]=0
        HOME_LEFT[$pkg]=0
        # Supervisor khởi động lại sau crash: app nào còn sống thì giữ nguyên, không force-stop.
        if [ "${IVY_RESUME:-0}" = "1" ] && [ -n "$(pidof "$pkg" 2>/dev/null)" ]; then
            log_line "AUTO resume: $pkg đang chạy, bỏ qua launch"
            continue
        fi
        printf ' %s-> Đang mở %s...%s\n' "$C_YELLOW" "$pkg" "$C_RESET"
        launch_package "$pkg" "$link"
        # Sau boot, mở lần lượt có khoảng nghỉ để máy không bị hết RAM.
        [ "$HEADLESS" -eq 1 ] && [ "$i" -lt $((${#PKGS[@]} - 1)) ] && sleep "$launch_gap"
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
        ui_top
        ui_section "ROBLOX AUTO-REJOIN"
        ui_line "Đang khởi động & vào game (${w}s)..."
        ui_bottom
        sleep 1
    done

    local webhook_url
    webhook_url="$(get_webhook_url)"
    if [ -n "$webhook_url" ] && [ "$interval" -gt 0 ] && [ "$AUTO_RUNNING" -eq 1 ]; then
        local parent_pid="$$"
        (
            while sleep "$((interval * 60))"; do
                kill -0 "$parent_pid" 2>/dev/null || exit 0
                send_webhook "$APP_NAME Uptime" \
                    "Auto rejoin đang chạy.
- Thiết bị: Android
- Thời gian: $(date '+%H:%M:%S %d/%m/%Y')" 5814783 >/dev/null 2>&1
            done
        ) &
        UPTIME_PID=$!
    fi

    local pid pids pkg_log state state_text age since_rejoin remain remain_text
    local ui_tick=0 fg_pkg="" ui_rc=0
    while [ "$AUTO_RUNNING" -eq 1 ]; do
        printf '\033[H'
        ui_top
        ui_section "ROBLOX IN-GAME MONITOR"
        now="$(date +%s)"
        LOGCAT_SNAPSHOT="$(logcat -d -t 1500 2>/dev/null)"
        if [ -z "$LOGCAT_SNAPSHOT" ]; then
            LOGCAT_SNAPSHOT="$(logcat -d 2>/dev/null | tail -n 1500)"
        fi

        # UI watchdog: khoảng 10 giây/lần, chỉ kiểm tra app đang foreground.
        # Chỉ rejoin khi app đã từng vào game (GAME_SEEN=1) rồi quay về Home,
        # tránh việc vừa mở app đã bị coi là đã rời game.
        ui_tick=$((ui_tick + 1))
        if [ "$HAS_UIAUTOMATOR" -eq 1 ] && [ "$HAS_DUMPSYS" -eq 1 ] \
            && [ $((ui_tick % 5)) -eq 0 ]; then
            fg_pkg="$(get_foreground_package)"
            if [ -n "$fg_pkg" ]; then
                for i in "${!PKGS[@]}"; do
                    pkg="${PKGS[$i]}"
                    [ "$pkg" = "$fg_pkg" ] || continue
                    age=$((now - ${CYCLE_START[$pkg]:-$now}))
                    since_rejoin=$((now - ${LAST_REJOIN[$pkg]:-0}))
                    [ "$age" -ge 15 ] || continue
                    [ "$since_rejoin" -ge 30 ] || continue
                    ui_is_home_screen
                    ui_rc=$?
                    if [ "$ui_rc" -eq 0 ]; then
                        if [ "${GAME_SEEN[$pkg]:-0}" -eq 1 ]; then
                            HOME_MISS[$pkg]=$(( ${HOME_MISS[$pkg]:-0} + 1 ))
                            if [ "${HOME_MISS[$pkg]}" -ge 2 ]; then
                                HOME_LEFT[$pkg]=1
                            fi
                        fi
                    elif [ "$ui_rc" -eq 1 ]; then
                        GAME_SEEN[$pkg]=1
                        HOME_MISS[$pkg]=0
                    fi
                done
            fi
        fi

        for i in "${!PKGS[@]}"; do
            pkg="${PKGS[$i]}"
            link="${LINKS[$i]}"
            [ "$AUTO_RUNNING" -eq 1 ] || break

            pids="$(pidof "$pkg" 2>/dev/null | tr '\n' ' ')"
            pid="${pids%% *}"
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
            elif [ "${HOME_LEFT[$pkg]:-0}" -eq 1 ]; then
                state="DISCONNECTED"
                state_text="ĐÃ RỜI GAME"
            else
                pkg_log="$(package_logcat "$pids")"
                [ -n "$pkg_log" ] || pkg_log="$LOGCAT_SNAPSHOT"
                if recent_disconnect "$pids" "$pkg_log"; then
                    state="DISCONNECTED"
                    state_text="MẤT KẾT NỐI"
                fi
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

            ui_line "${C_YELLOW}${pkg:0:20}${C_RESET}  ${C_GRAY}Rejoin:${C_RESET} ${CRASH_COUNT[$pkg]:-0}"
            ui_line "${C_GRAY}TT:${C_RESET} $state_text"
            ui_line "${C_GRAY}Reset sau:${C_RESET} $remain_text"
            ui_mid
        done

        ui_note "[Ctrl+C] quay lại menu"
        ui_bottom
        sleep 2
    done

    stop_uptime
    release_wake_lock
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
# Chạy nền + tự khởi động lại + Termux:Boot
# ------------------------------------------------------------
sup_pid_alive() {
    local pid
    pid="$(cat "$SUP_PID_FILE" 2>/dev/null)"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    # PID có thể bị tái sử dụng sau reboot: kiểm tra đúng là supervisor của mình.
    grep -qa -- '--supervise' "/proc/$pid/cmdline" 2>/dev/null
}

rotate_log() {
    local size
    size="$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)"
    if [ "${size:-0}" -gt 1048576 ]; then
        mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null
    fi
}

# Chờ Android boot xong + có mạng (hết hạn vẫn chạy tiếp, không kẹt vĩnh viễn).
wait_for_boot() {
    local i delay
    for ((i = 0; i < 120; i++)); do
        [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] && break
        sleep 2
    done
    delay="$(conf_get "$SETTINGS_FILE" BOOT_DELAY 2>/dev/null)"
    [[ "$delay" =~ ^[0-9]+$ ]] || delay=20
    log_line "SUP boot_completed, chờ thêm ${delay}s cho hệ thống ổn định"
    sleep "$delay"
    for ((i = 0; i < 30; i++)); do
        curl -s -m 5 -o /dev/null https://www.roblox.com/ && { log_line "SUP mạng sẵn sàng"; return 0; }
        sleep 3
    done
    log_line "SUP chưa thấy mạng sau ~90s, vẫn tiếp tục"
}

sup_on_term() {
    SUP_STOP=1
    [ -n "$SUP_CHILD" ] && kill -TERM "$SUP_CHILD" 2>/dev/null
}

# sleep có thể bị ngắt bởi tín hiệu TERM
sup_sleep() {
    sleep "$1" &
    wait $! 2>/dev/null
}

sup_notify() {
    [ -n "$(get_webhook_url)" ] || return 0
    ( send_webhook "$APP_NAME" "$1
- Thời gian: $(date '+%H:%M:%S %d/%m/%Y')" "${2:-5814783}" >/dev/null 2>&1 & ) 2>/dev/null
}

run_supervisor() {
    if sup_pid_alive; then
        printf 'Supervisor đã chạy (PID %s).\n' "$(cat "$SUP_PID_FILE")"
        return 1
    fi
    printf '%s' "$$" > "$SUP_PID_FILE" || { printf 'Không ghi được %s\n' "$SUP_PID_FILE"; return 1; }
    HEADLESS=1
    trap '' HUP
    trap sup_on_term TERM INT
    trap 'rm -f "$SUP_PID_FILE"' EXIT

    acquire_wake_lock
    # Chống Doze làm Termux ngủ khi chạy nền (bỏ qua nếu ROM không có).
    if [ "$HAS_DUMPSYS" -eq 1 ]; then
        dumpsys deviceidle whitelist +com.termux >/dev/null 2>&1
        dumpsys deviceidle whitelist +com.termux.boot >/dev/null 2>&1
    fi

    rotate_log
    local boot_start="${IVY_BOOT:-0}" resume=0 fails=0 started up rc delay last_notify=0 now
    log_line "SUP start PID=$$ boot=$boot_start"
    if [ "$boot_start" = "1" ]; then
        wait_for_boot
        sup_notify "Cloudphone vừa khởi động lại, tool tự chạy lại auto rejoin." 3066993
    else
        sup_notify "Đã bật chế độ chạy nền." 3066993
    fi

    while [ "$SUP_STOP" -eq 0 ]; do
        started="$(date +%s)"
        IVY_TUN_DIR="$CONF_DIR" IVY_RESUME="$resume" \
            "${BASH:-bash}" "$SELF_PATH" --auto >/dev/null 2>&1 &
        SUP_CHILD=$!
        log_line "SUP child PID=$SUP_CHILD (resume=$resume)"
        wait "$SUP_CHILD" 2>/dev/null
        rc=$?
        if [ "$SUP_STOP" -eq 1 ]; then
            # Đợi child tự dọn dẹp, quá 10s thì kill -9.
            for ((i = 0; i < 20; i++)); do
                kill -0 "$SUP_CHILD" 2>/dev/null || break
                sleep 0.5
            done
            kill -0 "$SUP_CHILD" 2>/dev/null && kill -KILL "$SUP_CHILD" 2>/dev/null
            break
        fi

        now="$(date +%s)"
        up=$((now - started))
        if [ "$up" -ge 120 ]; then fails=0; else fails=$((fails + 1)); fi
        delay=$((fails * 5))
        [ "$delay" -lt 5 ] && delay=5
        [ "$delay" -gt 60 ] && delay=60
        log_line "SUP child thoát rc=$rc sau ${up}s -> chạy lại sau ${delay}s (lỗi liên tiếp: $fails)"
        if [ "$rc" -ne 3 ] && [ $((now - last_notify)) -ge 600 ]; then
            sup_notify "Tool bị dừng (rc=$rc) sau ${up}s, đã tự chạy lại." 15158332
            last_notify="$now"
        fi
        resume=1
        sup_sleep "$delay"
    done
    log_line "SUP stop"
    release_wake_lock
    return 0
}

stop_supervisor() {
    local pid i
    if ! sup_pid_alive; then
        rm -f "$SUP_PID_FILE" 2>/dev/null
        printf 'Chế độ chạy nền không chạy.\n'
        return 0
    fi
    pid="$(cat "$SUP_PID_FILE")"
    kill -TERM "$pid" 2>/dev/null
    for ((i = 0; i < 40; i++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null
        command -v pkill >/dev/null 2>&1 && pkill -f -- "$SELF_PATH --auto" 2>/dev/null
    fi
    rm -f "$SUP_PID_FILE" 2>/dev/null
    log_line "SUP stopped by user"
    printf 'Đã dừng chế độ chạy nền (các app Roblox vẫn giữ nguyên).\n'
}

start_supervisor_detached() {
    local i
    if sup_pid_alive; then
        stop_supervisor >/dev/null
    fi
    (
        if command -v setsid >/dev/null 2>&1; then
            IVY_TUN_DIR="$CONF_DIR" setsid nohup "${BASH:-bash}" "$SELF_PATH" --supervise >/dev/null 2>&1 &
        else
            IVY_TUN_DIR="$CONF_DIR" nohup "${BASH:-bash}" "$SELF_PATH" --supervise >/dev/null 2>&1 &
        fi
    )
    for ((i = 0; i < 10; i++)); do
        sup_pid_alive && return 0
        sleep 0.5
    done
    return 1
}

supervisor_status() {
    if sup_pid_alive; then
        printf '%sChạy nền: ĐANG CHẠY (PID %s)%s\n' "$C_GREEN" "$(cat "$SUP_PID_FILE")" "$C_RESET"
    else
        printf '%sChạy nền: không chạy%s\n' "$C_YELLOW" "$C_RESET"
    fi
    if [ -f "$BOOT_STUB" ]; then
        printf 'Tự chạy khi boot: BẬT (%s)\n' "$BOOT_STUB"
    else
        printf 'Tự chạy khi boot: TẮT\n'
    fi
    printf '\nLog gần đây:\n'
    grep -E ' (SUP|REJOIN|AUTO) ' "$LOG_FILE" 2>/dev/null | tail -n 12
}

boot_enabled() { [ -f "$BOOT_STUB" ]; }

enable_boot() {
    local uid gid
    case "$SELF_PATH$CONF_DIR" in
        *"'"*) warn_msg "Đường dẫn chứa dấu nháy đơn ('), hãy đổi tên thư mục/file."; return 1 ;;
    esac
    mkdir -p "$BOOT_DIR" || { warn_msg "Không tạo được $BOOT_DIR"; return 1; }
    cat > "$BOOT_STUB" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
# Tạo bởi $APP_NAME v$SCRIPT_VERSION. Tắt tự chạy: dùng menu mục 12 hoặc xóa file này.
termux-wake-lock 2>/dev/null
IVY_SCRIPT='$SELF_PATH'
i=0
# /sdcard có thể chưa sẵn sàng ngay sau boot: chờ tối đa ~4 phút
while [ ! -f "\$IVY_SCRIPT" ] && [ "\$i" -lt 120 ]; do
    sleep 2
    i=\$((i + 1))
done
exec su -c "IVY_TUN_DIR='$CONF_DIR' IVY_BOOT=1 /data/data/com.termux/files/usr/bin/bash '\$IVY_SCRIPT' --supervise"
EOF
    # Termux:Boot chạy bằng user của Termux, không phải root -> phải chown, nếu không nó không đọc được file.
    uid="$(stat -c %u "$TERMUX_HOME" 2>/dev/null)"
    gid="$(stat -c %g "$TERMUX_HOME" 2>/dev/null)"
    if [[ "$uid" =~ ^[0-9]+$ ]]; then
        chown "$uid:$gid" "$TERMUX_HOME/.termux" "$BOOT_DIR" "$BOOT_STUB" 2>/dev/null
    fi
    chmod 700 "$BOOT_STUB"
    command -v restorecon >/dev/null 2>&1 && restorecon -R "$BOOT_DIR" >/dev/null 2>&1
    log_line "BOOT stub created: $BOOT_STUB"
    ok_msg "Đã tạo $BOOT_STUB"
    if ! pm path com.termux.boot >/dev/null 2>&1; then
        warn_msg "Chưa thấy app Termux:Boot. Cài nó (cùng nguồn với Termux), mở 1 lần, rồi mới có tác dụng."
    fi
}

disable_boot() {
    rm -f "$BOOT_STUB"
    log_line "BOOT stub removed"
    ok_msg "Đã tắt tự chạy khi khởi động."
}

manage_boot_autostart() {
    local choice v
    while true; do
        clear
        ui_top
        ui_title "CHẠY NỀN & TERMUX:BOOT"
        if sup_pid_alive; then
            ui_kv "Daemon" "${C_GREEN}ĐANG CHẠY${C_RESET} (PID $(cat "$SUP_PID_FILE"))"
        else
            ui_kv "Daemon" "${C_YELLOW}không chạy${C_RESET}"
        fi
        if boot_enabled; then
            ui_kv "Boot" "${C_GREEN}BẬT${C_RESET}"
        else
            ui_kv "Boot" "${C_YELLOW}TẮT${C_RESET}"
        fi
        if pm path com.termux.boot >/dev/null 2>&1; then
            ui_kv "Termux:Boot" "đã cài"
        else
            ui_kv "Termux:Boot" "${C_RED}CHƯA CÀI${C_RESET}"
        fi
        ui_kv "Reset/Delay" "$(conf_get "$SETTINGS_FILE" RESET_MIN 2>/dev/null || printf 30)p / $(conf_get "$SETTINGS_FILE" REJOIN_DELAY 2>/dev/null || printf 15)s"
        ui_note "Nền tự chạy lại khi tool crash; boot tự chạy khi máy khởi động."
        ui_section "CHỨC NĂNG"
        ui_item 1 "Bật tự chạy khi khởi động máy"
        ui_item 2 "Tắt tự chạy khi khởi động máy"
        ui_item 3 "Chạy nền ngay / khởi động lại nền (nạp lại cấu hình)"
        ui_item 4 "Dừng chạy nền"
        ui_item 5 "Xem trạng thái + log"
        ui_item 6 "Đổi chu kỳ reset / delay rejoin"
        ui_item 0 "Quay lại"
        ui_bottom
        ui_prompt "Lựa chọn: "
        read -r choice
        case "$choice" in
            1) enable_boot; sleep 2 ;;
            2) disable_boot; sleep 1 ;;
            3)
                if [ ! -s "$CONF_FILE" ]; then
                    warn_msg "Chưa cấu hình package. Vào mục 2 hoặc 4 trước."
                elif start_supervisor_detached; then
                    ok_msg "Đã chạy nền (PID $(cat "$SUP_PID_FILE"))."
                else
                    warn_msg "Không khởi động được. Xem log: $LOG_FILE"
                fi
                sleep 2
                ;;
            4) stop_supervisor; sleep 2 ;;
            5) clear; supervisor_status; pause_key ;;
            6)
                printf '%sChu kỳ reset (phút, 0=tắt): %s' "$C_WHITE" "$C_RESET"
                read -r v
                [[ "$v" =~ ^[0-9]+$ ]] && conf_set "$SETTINGS_FILE" RESET_MIN "$v"
                printf '%sDelay rejoin (giây): %s' "$C_WHITE" "$C_RESET"
                read -r v
                [[ "$v" =~ ^[0-9]+$ ]] && conf_set "$SETTINGS_FILE" REJOIN_DELAY "$v"
                ok_msg "Đã lưu. Bấm mục 3 để áp dụng cho chế độ nền."
                sleep 2
                ;;
            0|"") break ;;
        esac
    done
}

# ------------------------------------------------------------
# Menu chính
# ------------------------------------------------------------
main_menu() {
    while true; do
        clear
        local pkg_count webhook_text auto_text boot_text interval

        pkg_count="$(grep -c '=' "$CONF_FILE" 2>/dev/null || true)"
        pkg_count="${pkg_count:-0}"

        if [ -n "$(get_webhook_url)" ]; then
            webhook_text="đã đặt"
        else
            webhook_text="chưa đặt"
        fi

        interval="$(conf_get "$DISCORD_CONF" INTERVAL 2>/dev/null)"
        interval="${interval:-15}"

        if sup_pid_alive; then
            auto_text="ON"
        else
            auto_text="OFF"
        fi
        if boot_enabled; then boot_text="ON"; else boot_text="OFF"; fi

        ui_top
        ui_title "$APP_NAME  |  v$SCRIPT_VERSION"

        ui_section "TRẠNG THÁI"
        ui_kv2 "Packages" "$pkg_count" "Webhook" "$webhook_text"
        ui_kv2 "Daemon" "$auto_text" "Boot" "$boot_text"
        ui_kv "Uptime" "${interval} phút"

        ui_section "CHÍNH"
        ui_item 1 "Bật auto rejoin + uptime"
        ui_item 2 "Chọn app & gán link"
        ui_item 3 "Danh sách package đã chọn"
        ui_item 4 "Tự chọn tất cả với một link"
        ui_item 5 "Mở tất cả tab Roblox"

        ui_section "TÀI KHOẢN & PROFILE"
        ui_item 6 "Đăng nhập bằng cookie"
        ui_item 7 "Quản lý acc theo profile"
        ui_item 8 "Đăng xuất Roblox"
        ui_item 9 "Xuất cookies"

        ui_section "DISCORD & HỆ THỐNG"
        ui_item 10 "Cấu hình webhook / uptime"
        ui_item 11 "Xem package đã cài"
        ui_item 12 "Chạy nền & tự chạy khi khởi động (Termux:Boot)"
        ui_item 13 "Thoát"
        ui_bottom

        ui_prompt "Nhập lựa chọn: "
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
                ui_top
                ui_section "PACKAGE ĐÃ CÀI"
                get_all_installed_packages | while IFS= read -r p; do
                    ui_line "${C_GREEN}-${C_RESET} $p"
                done
                ui_bottom
                pause_key
                ;;
            12) manage_boot_autostart ;;
            13|0) cleanup ;;
            *) sleep 1 ;;
        esac
    done
}

case "${1:-}" in
    --auto)
        # Chạy auto rejoin không giao diện (do supervisor gọi).
        HEADLESS=1
        exec >/dev/null 2>&1 </dev/null
        start_auto_rejoin
        exit $?
        ;;
    --supervise)
        run_supervisor
        exit $?
        ;;
    --stop)
        stop_supervisor
        exit 0
        ;;
    --status)
        supervisor_status
        exit 0
        ;;
    --enable-boot)
        enable_boot
        exit $?
        ;;
    --disable-boot)
        disable_boot
        exit 0
        ;;
    -h|--help)
        printf 'Dùng: ivy-tun.sh [--supervise | --stop | --status | --enable-boot | --disable-boot]\n'
        printf '  (không tham số) mở menu\n'
        exit 0
        ;;
    "") main_menu ;;
    *)
        printf 'Tham số không hợp lệ: %s (xem --help)\n' "$1" >&2
        exit 2
        ;;
esac
