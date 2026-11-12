cat << 'EOF' | sudo tee /usr/local/bin/wtop >/dev/null
#!/bin/bash
# ==============================================================================
# wtop - Wazuh Terminal Operations Center (btop-style TUI for Wazuh Server)
# Version : v1.1.1
# License : MIT
# Requires: bash, tmux, jq, iproute2 (ss), awk, wazuh-manager (/var/ossec)
# ==============================================================================

set -u

WTOP_VERSION="v1.1.1"
SESSION="${WTOP_SESSION:-wtop}"
WAZUH_HOME="${WAZUH_HOME:-/var/ossec}"
RUN_DIR="/run/wtop"
MIN_W=80
MIN_H=24

BIN_CONTROL="${WAZUH_HOME}/bin/wazuh-control"
BIN_AGENT="${WAZUH_HOME}/bin/agent_control"
BIN_MANAGE="${WAZUH_HOME}/bin/manage_agents"
BIN_ANALYSISD="${WAZUH_HOME}/bin/wazuh-analysisd"
LOG_OSSEC="${WAZUH_HOME}/logs/ossec.log"
LOG_ALERTS="${WAZUH_HOME}/logs/alerts/alerts.json"

STATE_LEVEL="${RUN_DIR}/min_level"
STATE_LANG="${RUN_DIR}/lang"

# ANSI 色彩定義
RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[1;36m'
MAGENTA=$'\033[1;35m'
WHITE=$'\033[1;37m'
BOX_INACTIVE=$'\033[1;30m'   # 非焦點面板：低調鐵灰框線
BOX_ACTIVE=$'\033[1;36m'     # 當前焦點面板：高亮青色框線
TRACK_CLR=$'\033[1;30m'
DIM=$'\033[0;37m'
BOLD=$'\033[1m'
NC=$'\033[0m'

cleanup_tty() {
    printf '\033[?25h\033[?7h\033[0m'
}
trap cleanup_tty EXIT INT TERM

# 收到 USR1 訊號時立即喚醒重繪（供 tmux 切換視窗 Hook 觸發零延遲邊框變色）
trap ':' USR1

detect_default_lang() {
    local sys_locale="${LC_ALL:-${LC_MESSAGES:-${LANG:-C}}}"
    if ! echo "$sys_locale" | grep -qi "utf-\?8"; then
        echo "en"
    else
        echo "zh"
    fi
}

atomic_write() {
    local val="$1"
    local dest="$2"
    local tmp="${dest}.tmp.$$"
    printf '%s\n' "$val" > "$tmp" 2>/dev/null && mv -f "$tmp" "$dest" 2>/dev/null || true
}

load_i18n() {
    local lang="${1:-$(cat "$STATE_LANG" 2>/dev/null || detect_default_lang)}"
    if [ "$lang" = "zh" ]; then
        MSG_ERR_ROOT="需要 root 權限讀取 Wazuh，正在透過 sudo 提權..."
        MSG_ERR_WAZUH="錯誤：找不到 Wazuh 執行檔 (${WAZUH_HOME})。"
        MSG_MISSING_DEPS="缺少必要依賴套件："
        MSG_ASK_INSTALL="是否自動呼叫套件管理員安裝？(y/N): "
        MSG_CHECK_OK="[OK] wtop ${WTOP_VERSION} 語法、環境與安全性預檢全數通過！"
        MSG_UFW_TAB="ufw 封鎖排行"
        MSG_UFW_HDR="次數  點陣比例  來源 IP          目標埠"
        MSG_UFW_NONE="近期無 UFW BLOCK 攔截紀錄"
        MSG_P1514="1514(資料)"
        MSG_P1515="1515(註冊)"
        MSG_NAV_HINT="1-4/方向鍵:切換視窗 │ z:全螢幕放大 │ q:離開"
        MSG_PROMPT_INFO="輸入要查詢的 Agent 編號 (如 6 或 006，0 為本機): "
        MSG_PROMPT_ENTER="按 Enter 返回戰情室..."
        MSG_PROMPT_RST="輸入要重啟的 Agent 編號 (如 6 或 006): "
        MSG_PROMPT_DEL="輸入要刪除的 Agent 編號 (如 6 或 006，禁刪 000): "
        MSG_ERR_AID_FMT="錯誤：含非法字元！Agent 編號僅允許純數字 (例如 6 或 006)。"
        MSG_ERR_AID_000="安全攔截：禁止刪除或重啟 Wazuh Server 本機 (000)！"
        MSG_ERR_AID_NOTFOUND="找不到編號為 %s 的 Agent，請確認右上角清單！"
        MSG_RST_OK="已發送遠端重啟指令至 Agent"
        MSG_DEL_OK="已移除 Agent 金鑰與紀錄："
        MSG_PROMPT_MRST="立即重啟 wazuh-manager 生效？(y/N): "
        MSG_FIM_OK="已派發全員 FIM 掃描！"
        MSG_BLK_TITLE="=== [b] UFW 快速封鎖惡意外部 IP ==="
        MSG_BLK_PICK="輸入候選編號 (1-5) 或直接輸入合法 IP (空白取消): "
        MSG_BLK_INVALID="錯誤：含非法字元、IP 格式無效或系統未安裝 ufw！"
        MSG_BLK_SELF="安全攔截：禁止封鎖本機或您當前的 SSH 來源 IP"
        MSG_BLK_OK="已將 IP 寫入 UFW 第一條 DENY 規則："
        MSG_PRG_TITLE="=== [p] 一鍵清理所有離線 (Disconnected) Agent ==="
        MSG_PRG_NONE="目前所有 Agent 皆在線，無離線節點需清理！"
        MSG_PRG_ASK="確定要刪除上述離線 Agent 並重啟服務嗎？(y/N): "
        MSG_PRG_DONE="離線 Agent 清理完成！"
    else
        MSG_ERR_ROOT="Root privileges required. Elevating via sudo..."
        MSG_ERR_WAZUH="Error: Wazuh binaries not found in ${WAZUH_HOME}."
        MSG_MISSING_DEPS="Missing required packages:"
        MSG_ASK_INSTALL="Install missing packages via package manager? (y/N): "
        MSG_CHECK_OK="[OK] wtop ${WTOP_VERSION} syntax, environment & security checks passed!"
        MSG_UFW_TAB="ufw top blocked"
        MSG_UFW_HDR="CNT   BRAILLE   SOURCE IP        PORT"
        MSG_UFW_NONE="No recent UFW BLOCK records"
        MSG_P1514="1514(Data)"
        MSG_P1515="1515(Auth)"
        MSG_NAV_HINT="1-4/Arrows:Switch Pane │ z:Zoom │ q:Quit"
        MSG_PROMPT_INFO="Enter Agent ID to inspect (e.g. 6 or 006): "
        MSG_PROMPT_ENTER="Press Enter to return..."
        MSG_PROMPT_RST="Enter Agent ID to restart (e.g. 6 or 006): "
        MSG_PROMPT_DEL="Enter Agent ID to delete (except 000): "
        MSG_ERR_AID_FMT="Error: Invalid characters! Agent ID must be numeric."
        MSG_ERR_AID_000="Safety guard: Cannot delete/restart Manager (000)!"
        MSG_ERR_AID_NOTFOUND="Agent ID %s not found in registered list!"
        MSG_RST_OK="Restart command sent to Agent"
        MSG_DEL_OK="Removed Agent record:"
        MSG_PROMPT_MRST="Restart wazuh-manager now? (y/N): "
        MSG_FIM_OK="FIM scan dispatched!"
        MSG_BLK_TITLE="=== [b] UFW Block Malicious IP ==="
        MSG_BLK_PICK="Enter # (1-5) or valid IP to block (blank to cancel): "
        MSG_BLK_INVALID="Error: Illegal chars, invalid IP format, or ufw missing!"
        MSG_BLK_SELF="Safety guard: Cannot block localhost or your own SSH IP"
        MSG_BLK_OK="Blocked IP via UFW top rule:"
        MSG_PRG_TITLE="=== [p] Purge All Disconnected Agents ==="
        MSG_PRG_NONE="No disconnected agents found!"
        MSG_PRG_ASK="Purge all listed disconnected agents? (y/N): "
        MSG_PRG_DONE="Disconnected agents purged!"
    fi
}

show_help() {
    cat << HELP_EOF
wtop ${WTOP_VERSION} - Wazuh Terminal Operations Center (btop-style TUI)

Usage:
  wtop [OPTIONS]

Options:
  -v, --version      Show version number and exit
  -h, --help         Show this help message and exit
  --check            Run pre-flight environment & security checks
  --lang <zh|en>     Start wtop with specified language (zh or en)

Tmux & Navigation Hotkeys (Available in ALL Panels):
  [1] / [2] / [3] / [4]  Jump directly to Panel 1, 2, 3, or 4
  [Arrow Keys] / [Tab]   Move focus between panels (Active border lights up Cyan)
  [z]                    Toggle Fullscreen Zoom on current panel (like tmux Ctrl-b z)
  [f]                    Cycle Alert Level filter (Lv>=5 -> Lv>=10 -> Lv>=3)
  [l]                    Toggle UI Language (ZH / EN)
  [q]                    Quit wtop cleanly

SOC Action Hotkeys:
  [b] Block IP via UFW      [p] Purge disconnected agents
  [i] Inspect Agent info    [r] Restart specific Agent
  [d] Delete single Agent   [s] Dispatch FIM scan to all agents
HELP_EOF
}

preflight_check() {
    if [ "$EUID" -ne 0 ]; then
        echo "$MSG_ERR_ROOT"
        exec sudo -E "$0" "$@"
    fi
    if [ ! -x "$BIN_CONTROL" ] || [ ! -x "$BIN_AGENT" ] || [ ! -x "$BIN_MANAGE" ]; then
        echo "${RED}${MSG_ERR_WAZUH}${NC}" >&2
        exit 1
    fi

    local missing_pkgs=()
    command -v tmux >/dev/null 2>&1 || missing_pkgs+=("tmux")
    command -v jq   >/dev/null 2>&1 || missing_pkgs+=("jq")
    command -v ss   >/dev/null 2>&1 || missing_pkgs+=("iproute2")

    if [ "${#missing_pkgs[@]}" -gt 0 ]; then
        echo "${YELLOW}${MSG_MISSING_DEPS} ${missing_pkgs[*]}${NC}"
        read -r -p "$MSG_ASK_INSTALL" ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update && apt-get install -y "${missing_pkgs[@]}"
            elif command -v dnf >/dev/null 2>&1; then
                dnf install -y "${missing_pkgs[@]}"
            elif command -v yum >/dev/null 2>&1; then
                yum install -y "${missing_pkgs[@]}"
            else
                exit 1
            fi
        else
            exit 1
        fi
    fi

    mkdir -p "$RUN_DIR"
    chmod 700 "$RUN_DIR"
    [ ! -f "$STATE_LEVEL" ] && atomic_write 5 "$STATE_LEVEL"
    [ ! -f "$STATE_LANG" ]  && atomic_write "$(detect_default_lang)" "$STATE_LANG"
}

# ==========================================================
# 嚴格輸入清洗、正規化與驗證引擎 (Security & Normalization)
# ==========================================================

read_clean_line() {
    local prompt="$1"
    local raw_in=""
    read -r -n 45 -p "$prompt" raw_in || true
    LC_ALL=C printf '%s' "$raw_in" | tr -d '[:cntrl:][:space:]'
}

normalize_agent_id() {
    local raw="$1"
    local LC_ALL=C
    [ -z "$raw" ] && return 1
    local num_re='^[0-9]{1,5}$'
    if ! [[ "$raw" =~ $num_re ]]; then
        return 1
    fi
    local dec_val=$(( 10#$raw ))
    if [ "$dec_val" -lt 1000 ]; then
        printf '%03d' "$dec_val"
    else
        printf '%d' "$dec_val"
    fi
    return 0
}

agent_id_exists() {
    local norm_id="$1"
    [ "$norm_id" = "000" ] && return 0
    "$BIN_AGENT" -l 2>/dev/null | LC_ALL=C grep -qE "ID:[[:space:]]*0*${norm_id},"
}

is_valid_ip() {
    local ip="$1"
    local LC_ALL=C
    [ -z "$ip" ] && return 1
    local ipv4_re='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    local ipv6_re='^[0-9a-fA-F:]+$'
    if [[ "$ip" =~ $ipv4_re ]]; then
        local IFS='.'
        # shellcheck disable=SC2206
        local octets=($ip)
        local o
        for o in "${octets[@]}"; do
            [ "$(( 10#$o ))" -gt 255 ] && return 1
        done
        return 0
    elif [[ "$ip" =~ $ipv6_re ]] && [[ "$ip" == *:* ]] && [[ "$ip" != *:::* ]]; then
        return 0
    fi
    return 1
}

safe_restart_manager() {
    if [ -x "$BIN_ANALYSISD" ]; then
        "$BIN_ANALYSISD" -t >/dev/null 2>&1 || return 1
    fi
    systemctl restart wazuh-manager
}

read_hotkey() {
    local timeout="${1:-2}"
    REPLY_KEY=""
    local k1=""
    if ! read -r -s -t "$timeout" -n 1 k1; then
        return 1
    fi

    if [ "$k1" = $'\033' ]; then
        local seq=""
        read -r -s -t 0.05 -n 2 seq || true
        local extra=""
        read -r -s -t 0.01 -n 8 extra || true
        case "${seq}" in
            "[A") REPLY_KEY="ARROW_UP" ;;
            "[B") REPLY_KEY="ARROW_DOWN" ;;
            "[C") REPLY_KEY="ARROW_RIGHT" ;;
            "[D") REPLY_KEY="ARROW_LEFT" ;;
            *)    REPLY_KEY="ESC" ;;
        esac
        return 0
    elif [ "$k1" = $'\t' ]; then
        REPLY_KEY="TAB"
        return 0
    fi

    REPLY_KEY="$k1"
    return 0
}

handle_global_hotkey() {
    local key="$1"
    local cur_lvl cur_lang next_lvl
    cur_lvl=$(cat "$STATE_LEVEL" 2>/dev/null || echo 5)
    cur_lang=$(cat "$STATE_LANG" 2>/dev/null || echo "zh")

    case "$key" in
        1) tmux select-pane -t "${SESSION}:0.0" 2>/dev/null || true; return 0 ;;
        2) tmux select-pane -t "${SESSION}:0.1" 2>/dev/null || true; return 0 ;;
        3) tmux select-pane -t "${SESSION}:0.2" 2>/dev/null || true; return 0 ;;
        4) tmux select-pane -t "${SESSION}:0.3" 2>/dev/null || true; return 0 ;;
        TAB) tmux select-pane -t "${SESSION}:0.+" 2>/dev/null || true; return 0 ;;
        ARROW_UP)    tmux select-pane -U 2>/dev/null || true; return 0 ;;
        ARROW_DOWN)  tmux select-pane -D 2>/dev/null || true; return 0 ;;
        ARROW_LEFT)  tmux select-pane -L 2>/dev/null || true; return 0 ;;
        ARROW_RIGHT) tmux select-pane -R 2>/dev/null || true; return 0 ;;
        z|Z)
            [ -n "${TMUX_PANE:-}" ] && tmux resize-pane -Z -t "$TMUX_PANE" 2>/dev/null || true
            return 0
            ;;
        f|F)
            if [ "$cur_lvl" -eq 5 ]; then next_lvl=10
            elif [ "$cur_lvl" -eq 10 ]; then next_lvl=3
            else next_lvl=5; fi
            atomic_write "$next_lvl" "$STATE_LEVEL"
            return 0
            ;;
        l|L)
            if [ "$cur_lang" = "zh" ]; then atomic_write "en" "$STATE_LANG"
            else atomic_write "zh" "$STATE_LANG"; fi
            return 0
            ;;
        b|B|p|P|i|I|r|R|d|D|s|S)
            if [ "${CURRENT_PANE_NUM:-4}" != "4" ]; then
                tmux select-pane -t "${SESSION}:0.3" 2>/dev/null || true
                tmux send-keys -t "${SESSION}:0.3" "$key" 2>/dev/null || true
                return 0
            fi
            return 1
            ;;
        q|Q)
            cleanup_tty
            rm -rf "$RUN_DIR"
            tmux kill-session -t "$SESSION" 2>/dev/null || true
            exit 0
            ;;
    esac
    return 1
}

# ==========================================================
# btop 圓角框線 (支援 Active 面板動態高亮) 與 Braille 點陣引擎
# ==========================================================
repeat_horiz() {
    local len="$1"
    [ "$len" -lt 1 ] && len=1
    local spaces
    printf -v spaces '%*s' "$len" ''
    printf '%s' "${spaces// /─}"
}

update_active_box_color() {
    local is_active="0"
    if [ -n "${TMUX_PANE:-}" ]; then
        is_active=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_active}' 2>/dev/null || echo "0")
    fi
    if [ "$is_active" = "1" ]; then
        BOX_CLR="$BOX_ACTIVE"
        ACTIVE_MARK="${GREEN}●${NC}"
    else
        BOX_CLR="$BOX_INACTIVE"
        ACTIVE_MARK=""
    fi
}

make_braille_bar() {
    local val="${1:-0}"
    local max="${2:-10}"
    local width="${3:-6}"
    local color="${4:-$GREEN}"

    [ "$max" -le 0 ] && max=1
    [ "$val" -gt "$max" ] && val="$max"
    [ "$val" -lt 0 ] && val=0

    local total_steps=$(( width * 4 ))
    local filled_steps=$(( (val * total_steps + max / 2) / max ))
    [ "$val" -gt 0 ] && [ "$filled_steps" -eq 0 ] && filled_steps=1

    local full_cells=$(( filled_steps / 4 ))
    local rem_step=$(( filled_steps % 4 ))

    local bar_fill=""
    local bar_empty=""
    local i
    for (( i = 0; i < full_cells; i++ )); do
        bar_fill+="⣿"
    done

    if [ "$full_cells" -lt "$width" ]; then
        case "$rem_step" in
            1) bar_fill+="⣄" ;;
            2) bar_fill+="⣤" ;;
            3) bar_fill+="⣶" ;;
        esac
        local empty_start="$full_cells"
        [ "$rem_step" -gt 0 ] && empty_start=$(( empty_start + 1 ))
        for (( i = empty_start; i < width; i++ )); do
            bar_empty+="⣀"
        done
    fi

    printf "%s%s%s%s%s" "$color" "$bar_fill" "$TRACK_CLR" "$bar_empty" "$NC"
}

draw_btop_frame() {
    local cols="$1"
    local lines="$2"
    local num="$3"
    local title="$4"
    local right_badge="${5:-}"
    local bottom_bar="${6:-}"
    local brand_prefix="${7:-}"

    update_active_box_color

    local hbar
    hbar=$(repeat_horiz $(( cols - 2 )))

    printf '\033[1;1H%s╭%s╮%s' "$BOX_CLR" "$hbar" "$NC"
    if [ -n "$brand_prefix" ]; then
        printf '\033[1;2H%s─┐%s%s%s┌─┐%s%s%s%s%s%s┌─%s' \
            "$BOX_CLR" "$CYAN" "$brand_prefix" "$BOX_CLR" "$ACTIVE_MARK" "$RED" "$num" "$WHITE" "$title" "$BOX_CLR" "$NC"
    else
        printf '\033[1;2H%s─┐%s%s%s%s%s%s┌─%s' \
            "$BOX_CLR" "$ACTIVE_MARK" "$RED" "$num" "$WHITE" "$title" "$BOX_CLR" "$NC"
    fi

    if [ -n "$right_badge" ]; then
        local clean_badge
        clean_badge=$(echo "$right_badge" | sed 's/\x1b\[[0-9;]*m//g')
        local b_pos=$(( cols - ${#clean_badge} - 3 ))
        [ "$b_pos" -gt 18 ] && printf '\033[1;%dH%s┐%s%s%s┌─╮%s' "$b_pos" "$BOX_CLR" "$NC" "$right_badge" "$BOX_CLR" "$NC"
    fi
    printf '\033[1;%dH%s╮%s' "$cols" "$BOX_CLR" "$NC"

    local r
    for (( r = 2; r < lines; r++ )); do
        printf '\033[%d;1H%s│\033[K\033[%d;%dH%s│%s' "$r" "$BOX_CLR" "$r" "$cols" "$BOX_CLR" "$NC"
    done

    printf '\033[%d;1H%s╰%s╯%s' "$lines" "$BOX_CLR" "$hbar" "$NC"
    if [ -n "$bottom_bar" ]; then
        printf '\033[%d;2H%s' "$lines" "$bottom_bar"
    fi
    printf '\033[%d;1H%s╰%s\033[%d;%dH%s╯%s' "$lines" "$BOX_CLR" "$NC" "$lines" "$cols" "$BOX_CLR" "$NC"
}

draw_btop_divider() {
    local row="$1"
    local cols="$2"
    local subtitle="${3:-}"
    local hbar
    hbar=$(repeat_horiz $(( cols - 2 )))
    printf '\033[%d;1H%s├%s┤%s' "$row" "$BOX_CLR" "$hbar" "$NC"
    if [ -n "$subtitle" ]; then
        printf '\033[%d;2H%s─┐%s%s%s┌─%s' "$row" "$BOX_CLR" "$CYAN" "$subtitle" "$BOX_CLR" "$NC"
    fi
    printf '\033[%d;%dH%s┤%s' "$row" "$cols" "$BOX_CLR" "$NC"
}

put_row() {
    local row="$1"
    local cols="$2"
    local content="$3"
    printf '\033[%d;1H%s│%s\033[%d;3H%s\033[%d;%dH%s│%s' "$row" "$BOX_CLR" "$NC" "$row" "$content" "$row" "$cols" "$BOX_CLR" "$NC"
}

check_term_size_guard() {
    local win_dims
    win_dims=$(tmux display-message -p -t "$SESSION" '#{window_width} #{window_height} #{window_zoomed_flag}' 2>/dev/null || echo "80 24 0")
    local ww wh zoomed
    read -r ww wh zoomed <<< "$win_dims"

    if [ "${ww:-80}" -lt "$MIN_W" ] || [ "${wh:-24}" -lt "$MIN_H" ]; then
        if [ "${zoomed:-0}" -eq 0 ] && [ -n "${TMUX_PANE:-}" ]; then
            tmux resize-pane -Z -t "$TMUX_PANE" 2>/dev/null || true
        fi
        local w_color="$GREEN"
        local h_color="$GREEN"
        [ "$ww" -lt "$MIN_W" ] && w_color="$RED"
        [ "$wh" -lt "$MIN_H" ] && h_color="$RED"

        printf '\033[2J\033[H'
        local pad_top=$(( (wh - 5) / 2 ))
        [ "$pad_top" -lt 1 ] && pad_top=1
        printf "%*s" "$pad_top" "" | tr ' ' '\n'
        printf "%*s%sTerminal size too small:%s\n" $(( (ww - 24) / 2 )) "" "$BOLD" "$NC"
        printf "%*sWidth = %s%d%s Height = %s%d%s\n\n" $(( (ww - 22) / 2 )) "" "$w_color" "$ww" "$NC" "$h_color" "$wh" "$NC"
        printf "%*s%sNeeded for current config:%s\n" $(( (ww - 26) / 2 )) "" "$BOLD" "$NC"
        printf "%*sWidth = %d Height = %d" $(( (ww - 22) / 2 )) "" "$MIN_W" "$MIN_H"
        return 1
    fi
    return 0
}

# ==========================================================
# CLI 參數解析
# ==========================================================
CLI_MODE=""
ORIG_ARGS=("$@")
while [ "$#" -gt 0 ]; do
    case "$1" in
        -v|--version)
            echo "wtop ${WTOP_VERSION} (Wazuh Terminal Operations Center)"
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --check)
            CLI_MODE="check"
            ;;
        --lang)
            shift
            if [[ "${1:-}" =~ ^(zh|en)$ ]]; then
                mkdir -p "$RUN_DIR" 2>/dev/null || true
                atomic_write "$1" "$STATE_LANG"
            fi
            ;;
        --pane-*)
            CLI_MODE="$1"
            ;;
    esac
    shift
done

load_i18n

if [ "$CLI_MODE" = "check" ]; then
    preflight_check "${ORIG_ARGS[@]}"
    load_i18n
    echo "${GREEN}${MSG_CHECK_OK}${NC}"
    exit 0
fi

# ==========================================================
# 四大 TUI 面板主迴圈
# ==========================================================
case "$CLI_MODE" in
    --pane-status)
        CURRENT_PANE_NUM="1"
        printf '\033[?7l\033[?25l'
        while true; do
            load_i18n
            COLS=$(tput cols 2>/dev/null || echo 40)
            LINES=$(tput lines 2>/dev/null || echo 12)

            CONN_1514=$(ss -tn state established '( dport = :1514 or sport = :1514 )' 2>/dev/null | tail -n +2 | wc -l)
            CONN_1515=$(ss -tn state established '( dport = :1515 or sport = :1515 )' 2>/dev/null | tail -n +2 | wc -l)
            TOTAL_REMOTE=$("$BIN_AGENT" -l 2>/dev/null | grep "ID:" | grep -vc "000" || true)
            [ "${TOTAL_REMOTE:-0}" -lt 1 ] && TOTAL_REMOTE=6

            DBAR_W=4
            [ "$COLS" -ge 54 ] && DBAR_W=6
            RUN_BAR=$(make_braille_bar 10 10 "$DBAR_W" "$GREEN")
            STOP_BAR=$(make_braille_bar 0 10 "$DBAR_W" "$RED")

            STATUS_RAW=$("$BIN_CONTROL" status 2>/dev/null || true)
            RUN_CNT=$(echo "$STATUS_RAW" | grep -E "wazuh-(analysisd|remoted|authd|integratord|modulesd|syscheckd)" | grep -c "is running" || true)
            TOP_BAR=$(make_braille_bar "$RUN_CNT" 6 6 "$GREEN")
            BADGE="${TOP_BAR} ${WHITE}${RUN_CNT}/6${NC}"

            draw_btop_frame "$COLS" "$LINES" "¹" "daemons" "$BADGE" "" "wtop ${WTOP_VERSION}"

            mapfile -t DAEMON_LINES < <(
                echo "$STATUS_RAW" | \
                awk -v G="$GREEN" -v R="$RED" -v B="$BOX_CLR" -v N="$NC" -v rbar="$RUN_BAR" -v sbar="$STOP_BAR" '
                    /wazuh-(analysisd|remoted|authd|integratord|modulesd|syscheckd)/ {
                        sub(/wazuh-/, "", $1)
                        if ($0 ~ /is running/) {
                            st = rbar " " G "RUN " N
                        } else {
                            st = sbar " " R "STOP" N
                        }
                        items[++n] = sprintf("%-11s %s", $1, st)
                    }
                    END {
                        for (i = 1; i <= n; i += 2) {
                            if (i + 1 <= n) printf "%s %s│%s %s\n", items[i], B, N, items[i+1]
                            else printf "%s\n", items[i]
                        }
                    }
                '
            )
            cur_row=2
            for dline in "${DAEMON_LINES[@]}"; do
                [ "$cur_row" -lt $(( LINES - 2 )) ] && put_row "$cur_row" "$COLS" "$dline"
                cur_row=$(( cur_row + 1 ))
            done

            PBAR_W=5
            [ "$COLS" -ge 54 ] && PBAR_W=7
            BAR_1514=$(make_braille_bar "$CONN_1514" "$TOTAL_REMOTE" "$PBAR_W" "$CYAN")
            BAR_1515=$(make_braille_bar "$CONN_1515" 5 "$PBAR_W" "$YELLOW")
            PORT_LINE=$(printf "%s %s %s%d/%d%s %s│%s %s %s %s%d%s" \
                "$MSG_P1514" "$BAR_1514" "$GREEN" "$CONN_1514" "$TOTAL_REMOTE" "$NC" \
                "$BOX_CLR" "$NC" \
                "$MSG_P1515" "$BAR_1515" "$YELLOW" "$CONN_1515" "$NC")
            if [ "$cur_row" -lt $(( LINES - 1 )) ]; then
                put_row "$cur_row" "$COLS" "$PORT_LINE"
                cur_row=$(( cur_row + 1 ))
            fi

            if [ "$cur_row" -lt $(( LINES - 1 )) ]; then
                draw_btop_divider "$cur_row" "$COLS" "$MSG_UFW_TAB"
                cur_row=$(( cur_row + 1 ))
            fi
            if [ "$cur_row" -lt "$LINES" ]; then
                put_row "$cur_row" "$COLS" "${DIM}${MSG_UFW_HDR}${NC}"
                cur_row=$(( cur_row + 1 ))
            fi

            UFW_ROWS=$(( LINES - cur_row ))
            if [ "$UFW_ROWS" -ge 1 ]; then
                UFW_LOG="/var/log/ufw.log"
                [ ! -s "$UFW_LOG" ] && UFW_LOG="/var/log/syslog"
                if [ -f "$UFW_LOG" ]; then
                    mapfile -t UFW_RAW < <(
                        grep "UFW BLOCK" "$UFW_LOG" 2>/dev/null | tail -n 1500 | \
                        awk '{
                            src=""; dpt="";
                            if (match($0, /SRC=[0-9a-fA-F:\.]+/)) src=substr($0, RSTART+4, RLENGTH-4);
                            if (match($0, /DPT=[0-9]+/)) dpt=substr($0, RSTART+4, RLENGTH-4);
                            if (src != "") print src, dpt
                        }' | sort | uniq -c | sort -nr | head -n "$UFW_ROWS"
                    )
                    if [ "${#UFW_RAW[@]}" -gt 0 ]; then
                        MAX_UFW=$(echo "${UFW_RAW[0]}" | awk '{print $1}')
                        for uentry in "${UFW_RAW[@]}"; do
                            read -r ucnt usrc udpt <<< "$uentry"
                            UBAR=$(make_braille_bar "$ucnt" "$MAX_UFW" 6 "$RED")
                            uline=$(printf "%s%4d%s  %s  %s%-16s%s (Port: %s%s%s)" \
                                "$YELLOW" "$ucnt" "$NC" "$UBAR" "$MAGENTA" "$usrc" "$NC" "$CYAN" "$udpt" "$NC")
                            [ "$cur_row" -lt "$LINES" ] && put_row "$cur_row" "$COLS" "$uline"
                            cur_row=$(( cur_row + 1 ))
                        done
                    else
                        put_row "$cur_row" "$COLS" "${GREEN}${MSG_UFW_NONE}${NC}"
                    fi
                fi
            fi

            if read_hotkey 2; then
                handle_global_hotkey "$REPLY_KEY" || true
            fi
        done
        ;;

    --pane-agents)
        CURRENT_PANE_NUM="2"
        printf '\033[?7l\033[?25l'
        while true; do
            load_i18n
            COLS=$(tput cols 2>/dev/null || echo 40)
            LINES=$(tput lines 2>/dev/null || echo 12)
            ACTIVE_CNT=$("$BIN_AGENT" -lc 2>/dev/null | grep -c "ID:" || true)
            DISCONN_CNT=$("$BIN_AGENT" -ln 2>/dev/null | grep -c "ID:" || true)
            TOTAL_CNT=$(( ACTIVE_CNT + DISCONN_CNT ))

            AG_BAR=$(make_braille_bar "$ACTIVE_CNT" "$TOTAL_CNT" 6 "$GREEN")
            BADGE="${AG_BAR} Act:${GREEN}${ACTIVE_CNT}${NC} Dis:${RED}${DISCONN_CNT}${NC}"

            draw_btop_frame "$COLS" "$LINES" "²" "agents" "$BADGE"
            BOT_COUNT="${BOX_CLR}─┐${WHITE}${ACTIVE_CNT}/${TOTAL_CNT}${BOX_CLR}┌─╯${NC}"
            c_pos=$(( COLS - ${#ACTIVE_CNT} - ${#TOTAL_CNT} - 6 ))
            [ "$c_pos" -gt 4 ] && printf '\033[%d;%dH%s' "$LINES" "$c_pos" "$BOT_COUNT"

            NAME_W=$(( COLS - 25 ))
            [ "$NAME_W" -lt 8 ] && NAME_W=8
            MAX_AGENTS=$(( LINES - 3 ))
            [ "$MAX_AGENTS" -lt 1 ] && MAX_AGENTS=1

            HDR=$(printf "%s%-3s %-*s %-10s %s%s" "$DIM" "ID" "$NAME_W" "NAME" "IP" "STAT" "$NC")
            put_row 2 "$COLS" "$HDR"

            mapfile -t AGENT_LINES < <(
                "$BIN_AGENT" -l 2>/dev/null | grep "ID:" | head -n "$MAX_AGENTS" | \
                awk -F',' -v nw="$NAME_W" -v G="$GREEN" -v R="$RED" -v Y="$YELLOW" -v C="$CYAN" -v N="$NC" '{
                    id=$1; sub(/.*ID: */, "", id)
                    name=$2; sub(/.*Name: */, "", name)
                    ip=$3; sub(/.*IP: */, "", ip)
                    st=$4; sub(/^ */, "", st)

                    if (length(name) > nw) name = substr(name, 1, nw - 1) "+"
                    if (length(ip) > 10)   ip   = substr(ip, 1, 9) "+"

                    if (st ~ /Active/)            st_str = G "⣿ ACTV" N
                    else if (st ~ /Disconnected/) st_str = R "⣀ DISC" N
                    else                          st_str = Y "⡀ NEVR" N

                    printf "%s%-3s%s %-*s %-10s %s\n", C, id, N, nw, name, ip, st_str
                }'
            )
            cur_row=3
            for aline in "${AGENT_LINES[@]}"; do
                [ "$cur_row" -lt "$LINES" ] && put_row "$cur_row" "$COLS" "$aline"
                cur_row=$(( cur_row + 1 ))
            done

            if read_hotkey 2; then
                handle_global_hotkey "$REPLY_KEY" || true
            fi
        done
        ;;

    --pane-alerts)
        CURRENT_PANE_NUM="3"
        printf '\033[?7l\033[?25l'
        while true; do
            load_i18n
            COLS=$(tput cols 2>/dev/null || echo 40)
            LINES=$(tput lines 2>/dev/null || echo 12)
            MIN_LVL=$(cat "$STATE_LEVEL" 2>/dev/null || echo 5)
            MAX_ROWS=$(( LINES - 2 ))
            [ "$MAX_ROWS" -lt 1 ] && MAX_ROWS=1

            LVL_BAR=$(make_braille_bar "$MIN_LVL" 15 5 "$YELLOW")
            BADGE="${LVL_BAR} ${YELLOW}Lv>=${MIN_LVL}${NC}"
            draw_btop_frame "$COLS" "$LINES" "³" "alerts" "$BADGE"

            VER_TAG="wtop ${WTOP_VERSION}"
            v_pos=$(( COLS - ${#VER_TAG} - 5 ))
            [ "$v_pos" -gt 4 ] && printf '\033[%d;%dH%s─┐%s%s%s┌─╯%s' "$LINES" "$v_pos" "$BOX_CLR" "$CYAN" "$VER_TAG" "$BOX_CLR" "$NC"

            if [ -f "$LOG_ALERTS" ]; then
                mapfile -t ALERT_LINES < <(
                    tail -n 300 "$LOG_ALERTS" 2>/dev/null | \
                    jq --argjson lvl "$MIN_LVL" -r '
                        select(.rule.level >= $lvl) |
                        "\(.timestamp[11:19])|\(.rule.level)|\(.agent.name // "Mgr")|\(.rule.id)|\(.rule.description)\(if .data.srcip then " [" + .data.srcip + "]" else "" end)"
                    ' 2>/dev/null | tail -n "$MAX_ROWS" | \
                    awk -F'|' -v cols="$COLS" -v R="$RED" -v Y="$YELLOW" -v G="$GREEN" -v N="$NC" '{
                        tm=$1; lv=$2; ag=$3; rl=$4; ds=$5
                        if (length(ag) > 9) ag = substr(ag, 1, 8) "+"
                        prefix = sprintf("%s L%-2d %-9s R%-4s ", tm, lv, ag, rl)
                        rem = cols - length(prefix) - 4
                        if (rem < 5) rem = 5
                        if (length(ds) > rem) ds = substr(ds, 1, rem - 1) "+"

                        if (lv >= 10)     c = R
                        else if (lv >= 7) c = Y
                        else              c = G

                        printf "%s%s%s%s\n", c, prefix, ds, N
                    }'
                )
                cur_row=2
                for al in "${ALERT_LINES[@]}"; do
                    [ "$cur_row" -lt "$LINES" ] && put_row "$cur_row" "$COLS" "$al"
                    cur_row=$(( cur_row + 1 ))
                done
            fi

            if read_hotkey 2; then
                handle_global_hotkey "$REPLY_KEY" || true
            fi
        done
        ;;

    --pane-console)
        CURRENT_PANE_NUM="4"
        printf '\033[?7l'
        while true; do
            if ! check_term_size_guard; then
                sleep 1
                continue
            fi

            load_i18n
            COLS=$(tput cols 2>/dev/null || echo 40)
            LINES=$(tput lines 2>/dev/null || echo 12)
            CUR_LVL=$(cat "$STATE_LEVEL" 2>/dev/null || echo 5)
            CUR_LANG=$(cat "$STATE_LANG" 2>/dev/null || echo "zh")

            update_active_box_color

            TOP_BADGE="${RED}f${WHITE}:Lv>=${CUR_LVL} ${RED}l${WHITE}:${CUR_LANG} ${RED}z${WHITE}:Zoom${NC}"
            if [ "$CUR_LANG" = "zh" ]; then
                BOT_KEYS="${BOX_CLR}─┐${RED}b${WHITE}封鎖${BOX_CLR}┌┐${RED}p${WHITE}清理${BOX_CLR}┌┐${RED}i${WHITE}詳情${BOX_CLR}┌┐${RED}r${WHITE}重啟${BOX_CLR}┌┐${RED}d${WHITE}刪除${BOX_CLR}┌┐${RED}s${WHITE}FIM${BOX_CLR}┌┐${RED}q${WHITE}離開${BOX_CLR}┌${NC}"
            else
                BOT_KEYS="${BOX_CLR}─┐${RED}b${WHITE}Blk${BOX_CLR}┌┐${RED}p${WHITE}Prg${BOX_CLR}┌┐${RED}i${WHITE}Info${BOX_CLR}┌┐${RED}r${WHITE}Rst${BOX_CLR}┌┐${RED}d${WHITE}Del${BOX_CLR}┌┐${RED}s${WHITE}FIM${BOX_CLR}┌┐${RED}q${WHITE}Quit${BOX_CLR}┌${NC}"
            fi

            draw_btop_frame "$COLS" "$LINES" "⁴" "logs & control" "$TOP_BADGE" "$BOT_KEYS"

            LOG_ROWS=$(( LINES - 3 ))
            [ "$LOG_ROWS" -lt 1 ] && LOG_ROWS=1

            if [ -f "$LOG_OSSEC" ]; then
                mapfile -t OSLINES < <(
                    grep -E "wazuh-authd|ERROR|WARNING" "$LOG_OSSEC" 2>/dev/null | tail -n "$LOG_ROWS" | \
                    awk -v cols="$COLS" -v R="$RED" -v Y="$YELLOW" -v C="$CYAN" -v N="$NC" '{
                        line = $0
                        sub(/^[0-9\/]+ /, "", line)
                        sub(/wazuh-/, "", line)
                        maxw = cols - 4
                        if (length(line) > maxw) line = substr(line, 1, maxw - 1) "+"
                        if (line ~ /ERROR/)        printf "%s%s%s\n", R, line, N
                        else if (line ~ /WARNING/) printf "%s%s%s\n", Y, line, N
                        else                       printf "%s%s%s\n", C, line, N
                    }'
                )
                cur_row=2
                for oline in "${OSLINES[@]}"; do
                    [ "$cur_row" -lt $(( LINES - 1 )) ] && put_row "$cur_row" "$COLS" "$oline"
                    cur_row=$(( cur_row + 1 ))
                done
            fi

            put_row $(( LINES - 1 )) "$COLS" "${DIM}${MSG_NAV_HINT}${NC}"

            printf '\033[?25l\033[%d;%dH' "$LINES" "$COLS"
            if ! read_hotkey 2; then
                continue
            fi

            if handle_global_hotkey "$REPLY_KEY"; then
                continue
            fi

            case "$REPLY_KEY" in
                b|B)
                    printf '\033[?25h\033[2J\033[H'
                    echo -e "${CYAN}${MSG_BLK_TITLE}${NC}"
                    UFW_LOG="/var/log/ufw.log"
                    [ ! -s "$UFW_LOG" ] && UFW_LOG="/var/log/syslog"
                    mapfile -t CAND_IPS < <(
                        {
                            [ -f "$UFW_LOG" ] && grep "UFW BLOCK" "$UFW_LOG" 2>/dev/null | tail -n 1500 | \
                                awk '{if (match($0, /SRC=[0-9a-fA-F:\.]+/)) print substr($0, RSTART+4, RLENGTH-4)}'
                            [ -f "$LOG_ALERTS" ] && tail -n 300 "$LOG_ALERTS" 2>/dev/null | \
                                jq -r 'select(.rule.level >= 5 and .data.srcip != null) | .data.srcip' 2>/dev/null
                        } | sort | uniq -c | sort -nr | head -n 5 | awk '{print $2, "(" $1 " hits)"}'
                    )
                    idx=1
                    for item in "${CAND_IPS[@]}"; do
                        echo -e "  ${YELLOW}[${idx}]${NC} ${item}"
                        idx=$(( idx + 1 ))
                    done
                    echo ""
                    blk_in=$(read_clean_line "$MSG_BLK_PICK")
                    echo ""
                    TARGET_IP=""
                    if [[ "$blk_in" =~ ^[1-5]$ ]] && [ "$blk_in" -le "${#CAND_IPS[@]}" ]; then
                        TARGET_IP=$(echo "${CAND_IPS[$((blk_in-1))]}" | awk '{print $1}')
                    elif [ -n "$blk_in" ]; then
                        TARGET_IP="$blk_in"
                    fi

                    if [ -n "$TARGET_IP" ]; then
                        if ! command -v ufw >/dev/null 2>&1 || ! is_valid_ip "$TARGET_IP"; then
                            echo -e "${RED}${MSG_BLK_INVALID}${NC}"
                        else
                            MY_SSH_IP=$(echo "${SSH_CONNECTION:-}" | awk '{print $1}')
                            if [ "$TARGET_IP" = "127.0.0.1" ] || [ "$TARGET_IP" = "::1" ] || { [ -n "$MY_SSH_IP" ] && [ "$TARGET_IP" = "$MY_SSH_IP" ]; }; then
                                echo -e "${RED}${MSG_BLK_SELF}: ${TARGET_IP}${NC}"
                            else
                                ufw insert 1 deny from "$TARGET_IP" to any comment "wtop-block"
                                echo -e "${GREEN}${MSG_BLK_OK} ${TARGET_IP}${NC}"
                            fi
                        fi
                        echo ""
                        read -r -p "$MSG_PROMPT_ENTER" _
                    fi
                    ;;
                p|P)
                    printf '\033[?25h\033[2J\033[H'
                    echo -e "${CYAN}${MSG_PRG_TITLE}${NC}"
                    mapfile -t DISC_LIST < <("$BIN_AGENT" -ln 2>/dev/null | grep "ID:" || true)
                    if [ "${#DISC_LIST[@]}" -eq 0 ]; then
                        echo -e "\n${GREEN}${MSG_PRG_NONE}${NC}\n"
                        read -r -p "$MSG_PROMPT_ENTER" _
                    else
                        for d_ag in "${DISC_LIST[@]}"; do
                            echo -e "  ${RED}●${NC} ${d_ag}"
                        done
                        echo ""
                        p_ans=$(read_clean_line "$MSG_PRG_ASK")
                        echo ""
                        if [[ "$p_ans" =~ ^[Yy]$ ]]; then
                            for d_ag in "${DISC_LIST[@]}"; do
                                raw_did=$(echo "$d_ag" | awk -F',' '{sub(/.*ID: */, "", $1); gsub(/[^0-9]/, "", $1); print $1}')
                                if norm_did=$(normalize_agent_id "$raw_did") && [ "$norm_did" != "000" ]; then
                                    OSSEC_ACTION_CONFIRMED=y "$BIN_MANAGE" -r "$norm_did"
                                fi
                            done
                            safe_restart_manager
                            echo -e "\n${GREEN}${MSG_PRG_DONE}${NC}\n"
                            read -r -p "$MSG_PROMPT_ENTER" _
                        fi
                    fi
                    ;;
                i|I)
                    printf '\033[?25h\033[%d;3H\033[K' $(( LINES - 1 ))
                    raw_aid=$(read_clean_line "$MSG_PROMPT_INFO")
                    if [ -n "$raw_aid" ]; then
                        if ! norm_aid=$(normalize_agent_id "$raw_aid"); then
                            put_row $(( LINES - 1 )) "$COLS" "${RED}${MSG_ERR_AID_FMT}${NC}"
                            sleep 1.5
                        elif ! agent_id_exists "$norm_aid"; then
                            # shellcheck disable=SC2059
                            err_msg=$(printf "$MSG_ERR_AID_NOTFOUND" "$norm_aid")
                            put_row $(( LINES - 1 )) "$COLS" "${RED}${err_msg}${NC}"
                            sleep 1.5
                        else
                            clear
                            "$BIN_AGENT" -i -u "$norm_aid"
                            echo ""
                            read -r -p "$MSG_PROMPT_ENTER" _
                        fi
                    fi
                    ;;
                r|R)
                    printf '\033[?25h\033[%d;3H\033[K' $(( LINES - 1 ))
                    raw_aid=$(read_clean_line "$MSG_PROMPT_RST")
                    if [ -n "$raw_aid" ]; then
                        if ! norm_aid=$(normalize_agent_id "$raw_aid"); then
                            put_row $(( LINES - 1 )) "$COLS" "${RED}${MSG_ERR_AID_FMT}${NC}"
                            sleep 1.5
                        elif [ "$norm_aid" = "000" ]; then
                            put_row $(( LINES - 1 )) "$COLS" "${RED}${MSG_ERR_AID_000}${NC}"
                            sleep 1.5
                        elif ! agent_id_exists "$norm_aid"; then
                            # shellcheck disable=SC2059
                            err_msg=$(printf "$MSG_ERR_AID_NOTFOUND" "$norm_aid")
                            put_row $(( LINES - 1 )) "$COLS" "${RED}${err_msg}${NC}"
                            sleep 1.5
                        else
                            "$BIN_AGENT" -R -u "$norm_aid" >/dev/null 2>&1
                            put_row $(( LINES - 1 )) "$COLS" "${GREEN}${MSG_RST_OK}: ${norm_aid}${NC}"
                            sleep 1.2
                        fi
                    fi
                    ;;
                d|D)
                    printf '\033[?25h\033[%d;3H\033[K' $(( LINES - 1 ))
                    raw_aid=$(read_clean_line "$MSG_PROMPT_DEL")
                    if [ -n "$raw_aid" ]; then
                        if ! norm_aid=$(normalize_agent_id "$raw_aid"); then
                            put_row $(( LINES - 1 )) "$COLS" "${RED}${MSG_ERR_AID_FMT}${NC}"
                            sleep 1.5
                        elif [ "$norm_aid" = "000" ]; then
                            put_row $(( LINES - 1 )) "$COLS" "${RED}${MSG_ERR_AID_000}${NC}"
                            sleep 1.5
                        elif ! agent_id_exists "$norm_aid"; then
                            # shellcheck disable=SC2059
                            err_msg=$(printf "$MSG_ERR_AID_NOTFOUND" "$norm_aid")
                            put_row $(( LINES - 1 )) "$COLS" "${RED}${err_msg}${NC}"
                            sleep 1.5
                        else
                            OSSEC_ACTION_CONFIRMED=y "$BIN_MANAGE" -r "$norm_aid" >/dev/null 2>&1
                            put_row $(( LINES - 1 )) "$COLS" "${GREEN}${MSG_DEL_OK} ${norm_aid}${NC}"
                            sleep 1
                            printf '\033[%d;3H\033[K' $(( LINES - 1 ))
                            rst=$(read_clean_line "$MSG_PROMPT_MRST")
                            [[ "$rst" =~ ^[Yy]$ ]] && safe_restart_manager
                        fi
                    fi
                    ;;
                s|S)
                    "$BIN_AGENT" -r -a >/dev/null 2>&1
                    put_row $(( LINES - 1 )) "$COLS" "${GREEN}${MSG_FIM_OK}${NC}"
                    sleep 1
                    ;;
            esac
        done
        ;;

    *)
        preflight_check "${ORIG_ARGS[@]}"
        load_i18n

        if tmux has-session -t "$SESSION" 2>/dev/null; then
            exec tmux -2 attach-session -t "$SESSION"
        fi

        tmux -2 new-session -d -s "$SESSION" -n "SOC" "$0 --pane-status"
        tmux set-option -t "$SESSION" mouse on
        tmux set-option -t "$SESSION" status off

        tmux set-option -t "$SESSION" pane-border-style fg=brightblack
        tmux set-option -t "$SESSION" pane-active-border-style fg=brightcyan,bold
        tmux set-option -t "$SESSION" pane-border-lines heavy 2>/dev/null || true

        tmux split-window -h -t "${SESSION}:0.0" "$0 --pane-agents"
        tmux split-window -v -t "${SESSION}:0.0" "$0 --pane-alerts"
        tmux split-window -v -t "${SESSION}:0.2" "$0 --pane-console"

        tmux set-hook -t "$SESSION" after-select-pane \
            "run-shell 'pkill -USR1 -f \"wtop --pane-\" 2>/dev/null || true'" 2>/dev/null || true

        tmux select-pane -t "${SESSION}:0.3"
        exec tmux -2 attach-session -t "$SESSION"
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/wtop
bash -n /usr/local/bin/wtop && wtop --check