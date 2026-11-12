# wtop — Wazuh Terminal Operations Center ⚡

![Version](https://img.shields.io/badge/version-v1.1.0-cyan.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)
![Stack](https://img.shields.io/badge/stack-Pure%20Bash%20%2B%20tmux-orange.svg)

**`wtop`** 是一款致敬 [`btop`](https://github.com/aristocratos/btop) 視覺美學的 **Wazuh Server 終端機戰情室（TUI）**。  
專為追求 **「極致零堆疊（Zero-Stack）」** 的系統管理員與 SOC 維運人員打造——不裝 Docker、不開額外 Web 服務、不依賴第三方通訊軟體或龐大的 Python 套件，只要透過 SSH 登入主機敲下 `wtop`，即可在單一終端機畫面掌握全局並執行主動防禦。

> **English Summary**: `wtop` is a zero-dependency, `btop`-styled terminal dashboard for Wazuh Server built purely with `bash`, `tmux`, `jq`, and standard Linux utilities. Monitor Wazuh daemons, track active/disconnected agents, stream live security alerts, and block malicious IPs via UFW with a single keystroke.

---

## 📸 畫面預覽 (Screenshot)

<!-- 將你的截圖上傳至 GitHub 專案後，修改下方圖片路徑即可顯示 -->
![wtop Screenshot](assets/screenshot.jpg)

---

## ✨ 核心特色 (Key Features)

* 🎨 **致敬 `btop` 的純終端機美學**：
  * 採用 `btop` 經典圓角外框（`╭─╮` / `╰─╯`）、凹槽標題膠囊（`─┐¹daemons┌─`）與平滑 **Braille 點陣視覺進度條（`⣀⣤⣶⣿`）**。
  * **動態焦點高亮邊框**：切換視窗時，當前選中的面板外框會自動亮起 **高亮青色（Bright Cyan）** 與綠燈 `●`，視覺焦點一目了然。
  * **響應式視窗尺寸保護**：當 SSH 視窗過度縮小（低於 `80x24`）時，自動觸發全螢幕尺寸攔截提示，並支援長字串 `+` 號自動截斷，絕不折行破版。
* 🛡️ **四大維度即時監控（100% 原生底層整合）**：
  1. **`¹daemons & ufw`**：即時監控 6 大 Wazuh 核心微服務狀態、Port `1514`（資料連線）與 `1515`（註冊連線）即時連線數，以及 **UFW 防火牆封鎖排行榜 Top 5**。
  2. **`²agents`**：即時統計在線（`ACTV`）與離線（`DISC`）Agent 數量與狀態清單。
  3. **`³alerts`**：即時解析 `/var/ossec/logs/alerts/alerts.json` 安全告警流，依危險等級自動分色（紅/黃/綠）並支援動態切換過濾門檻（`Lv>=5` / `Lv>=10` / `Lv>=3`）。
  4. **`⁴logs & control`**：即時監控 `wazuh-authd` 註冊事件與系統 `ERROR`/`WARNING` 日誌，並內建單鍵快速反應操作台。
* ⚡ **單鍵主動防禦與生命周期管理**：
  * **`[b]` 一鍵封鎖惡意 IP**：自動彙整 UFW 攔截排行與高危告警中的攻擊者 IP，輸入編號 `1`–`5` 即可透過 `ufw insert 1 deny` 置頂封鎖。
  * **`[p]` 一鍵清理離線殭屍 Agent**：自動列出所有 `Disconnected` 節點，確認後批次移除金鑰並安全重啟服務。
  * 支援單鍵查詢 Agent 詳情（`[i]`）、遠端重啟 Agent（`[r]`）、刪除單一 Agent（`[d]`）與派發全員 FIM 掃描（`[s]`）。
* 🔒 **資安級輸入正規化與防呆機制**：
  * **Agent ID 自動正規化**：輸入 `6` 自動補零為 `006`，內建十進位強制轉型防止 `008`/`009` 八進位解析崩潰，並硬性攔截刪除或重啟 `000`（Wazuh Manager 本機）。
  * **防自鎖保護**：UFW 封鎖功能自動偵測並禁止封鎖 `127.0.0.1`、`::1` 與管理員當前的 `SSH_CONNECTION` 來源 IP。
  * **雙語系無縫切換**：自動偵測終端機 UTF-8 環境，並支援按 **`[l]`** 鍵即時切換 **繁體中文 / English** 介面。

---

## 🚀 快速安裝 (Quick Start)

### 系統需求 (Prerequisites)
* 已安裝 **Wazuh Server (Manager)**（預設路徑 `/var/ossec`）
* Linux 系統工具：`bash`、`tmux`、`jq`、`iproute2 (ss)`、`awk`（首次執行 `wtop` 時若缺少套件，內建 Pre-flight Check 會自動詢問並協助安裝）

### 一行指令安裝 (One-Liner Install)
```bash
sudo curl -fsSL [https://raw.githubusercontent.com/](https://raw.githubusercontent.com/)<你的GitHub帳號>/wtop/main/wtop -o /usr/local/bin/wtop && sudo chmod +x /usr/local/bin/wtop
```

### 手動 Git Clone 安裝
```bash
git clone [https://github.com/](https://github.com/)<你的GitHub帳號>/wtop.git
cd wtop
sudo install -m 0755 wtop /usr/local/bin/wtop
```

---

## ⌨️ 操作與快捷鍵說明 (Hotkeys & Usage)

在終端機直接輸入 `wtop` 即可啟動戰情室：

```bash
wtop
```

### 1. 視窗導航與全域熱鍵（在任一面板皆可觸發）
| 按鍵 | 功能說明 |
| :--- | :--- |
| **`1` / `2` / `3` / `4`** | 直接跳轉至第 1、2、3、4 號面板（被選中的面板外框會亮起青色高亮） |
| **`↑` `↓` `←` `→` / `Tab`** | 在四個面板之間移動焦點（亦支援直接用 **滑鼠左鍵點擊** 面板） |
| **`z`** | **全螢幕放大 / 還原** 當前選中的面板（同 `tmux` 原生 `Ctrl-b z` 手感） |
| **`f`** | 循環切換左下角告警流的最低顯示等級（`Lv>=5` ➔ `Lv>=10` ➔ `Lv>=3`） |
| **`l`** | 即時切換介面語系（**繁體中文** ⇄ **English**） |
| **`q`** | 安全清理暫存檔並關閉 `wtop` 戰情室 |

### 2. SOC 維運與主動防禦熱鍵
| 按鍵 | 功能說明 | 底層執行動作 |
| :--- | :--- | :--- |
| **`b`** | **UFW 快速封鎖惡意 IP** | 自動列出前 5 名攻擊 IP 供選取（或手動輸入），執行 `ufw insert 1 deny from <IP>` |
| **`p`** | **批次清理離線 Agent** | 列出所有 `Disconnected` 節點，確認後批次執行 `manage_agents -r` 並重啟服務 |
| **`i`** | **檢視單一 Agent 詳情** | 輸入編號（如 `6` 或 `006`）呼叫 `agent_control -i -u` 檢視系統與最後連線時間 |
| **`r`** | **遠端重啟指定 Agent** | 輸入編號呼叫 `agent_control -R -u` 遠端重啟該 Agent 服務 |
| **`d`** | **刪除單一指定 Agent** | 輸入編號（禁刪 `000`）呼叫 `manage_agents -r` 移除該節點 |
| **`s`** | **強制全員 FIM 掃描** | 呼叫 `agent_control -r -a` 立即對所有在線 Agent 派發 Syscheck / Rootcheck 掃描 |

---

## 🛠️ 命令列參數 (CLI Options)

```text
Usage:
  wtop [OPTIONS]

Options:
  -v, --version      顯示版本號 (v1.1.0)
  -h, --help         顯示完整說明與快捷鍵清單
  --check            僅執行啟動前環境與依賴套件檢查 (Pre-flight Check)
  --lang <zh|en>     強制指定啟動語系 (zh 繁體中文 / en 英文)
```

---

## 📄 授權條款 (License)

本專案採用 [MIT License](LICENSE) 開源授權，歡迎自由修改、Fork 與提交 PR！
