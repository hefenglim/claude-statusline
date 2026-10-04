# Claude Code 狀態列（可攜版）

```
v2.1.220 │ Opus 5 │ think:xhigh │ ctx:31% │ $3.41 │ +156/-23 │ 5h:42% (2h13m) │ 7d:18% (4d6h) │ …/components/statusline
```

| 區段 | 來源欄位 | 說明 |
|---|---|---|
| `vX.Y.Z` | `version` | **Claude Code CLI 版本**（非模型版本），行首前綴，次要色 |
| 模型 | `model.display_name` | 亮白粗體，對比最強 |
| think | `effort.level`，無此鍵時退回 `thinking.enabled` | 顯示推理效力等級或 on/off |
| ctx | `context_window.used_percentage` | 目前 context 用量 |
| `$` | `cost.total_cost_usd` | Claude Code 自己算的**實際金額**，與 `/cost` 同源，非依單價估算 |
| `+A/-R` | `cost.total_lines_added` / `total_lines_removed` | 本 session 改動行數，獨立欄位，**兩者皆為 0 時隱藏** |
| 5h / 7d | `rate_limits.{five_hour,seven_day}` | 額度用量 +（距離重置倒數） |
| 目錄 | `workspace.current_dir` | **末兩層**，有被截斷時前面加 `…/`。次要色，置於**行末** |

> 目錄放在最後而非開頭：它是麵包屑不是標題，擺行末可讓左邊界固定，切換目錄時各項指標不會左右跳動。

> **寬度提醒**：全部欄位同時出現時約 **138 字**（實測下方範例：版本 + 長模型名 + 五位數行數 + 兩個額度窗口 + 目錄；目錄名越長越寬），窄終端會換行：
>
> ```
> v2.1.220 │ Opus 5 (1M context) │ think:xhigh │ ctx:88%! │ $24.90 │ +9812/-3140 │ 5h:93%! (2h13m) │ 7d:18% (4d6h) │ …/components/statusline
> ```
>
> 平時多半短得多（例如剛開 session 沒有改動行數）。想縮短就從 `render` 段刪掉不需要的 `line+=` 那一行即可 —— 一行一段，互不相依。

---

## 需求

* **bash**。Windows 用 Git Bash（安裝 Git for Windows 即有）；macOS / Linux 用內建的即可。
* 不需要 `jq`、`awk`、`python`、`bc`。腳本只用 bash 內建功能。
* bash 3.2 以上皆可（macOS 內建版本）。詳見下方「相容性」。

## 安裝：全域（所有專案）

1. 放置腳本：

   ```bash
   mkdir -p ~/.claude
   cp statusline-command.sh ~/.claude/statusline-command.sh
   chmod +x ~/.claude/statusline-command.sh
   ```

2. 在 `~/.claude/settings.json` 加入 `statusLine` 區塊（保留檔案裡其他既有設定，只加這一段）：

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline-command.sh"
     }
   }
   ```

3. 重開 Claude Code。

## 安裝：單一專案

放在專案內並改用專案設定檔，優先權高於全域設定：

```bash
mkdir -p .claude
cp statusline-command.sh .claude/statusline-command.sh
chmod +x .claude/statusline-command.sh
```

`<專案>/.claude/settings.json`：

```json
{
  "statusLine": {
    "type": "command",
    "command": "$CLAUDE_PROJECT_DIR/.claude/statusline-command.sh"
  }
}
```

> `settings.json` 會進版控、與團隊共用；只想自己看就寫進 `settings.local.json`（預設已被 gitignore）。

### 設定優先順序（高 → 低）

```
企業政策 managed-settings.json
  → <專案>/.claude/settings.local.json
  → <專案>/.claude/settings.json
  → ~/.claude/settings.json          ← 全域
```

某個專案想**停用**：Claude Code 沒有「關閉」值可寫，實務做法是在該專案指向一個只印空字串的腳本。

---

## 客製化

門檻集中在腳本頂端，改完即生效（不需重啟）：

```bash
CTX_WARN=60      # context %，達此值轉黃
CTX_ALERT=85     # context %，達此值轉洋紅並加 '!'
COST_WARN=500    # 美分，達 $5.00 轉黃
COST_ALERT=2000  # 美分，達 $20.00 轉洋紅
RL_WARN=70       # 額度 %，達此值轉黃
RL_ALERT=90      # 額度 %，達此值轉洋紅並加 '!'
```

### 配色

原設計針對 **深色 + daltonized（色盲友善）** 主題，嚴重度走 **藍 → 黃 → 洋紅**，刻意避開紅綠對比；警戒層級同時附加 `!`，資訊不單靠顏色傳達。

```bash
SEP=$'\033[0;90m'       # #767676   4:1  分隔線
C_MODEL=$'\033[1;97m'   # #F2F2F2  18:1  模型名，最粗最亮
C_THINK=$'\033[1;96m'   # #61D6D6  11:1  平靜狀態下唯一的色相
CALM=$'\033[0;97m'      # #F2F2F2  18:1  一般指標
WARN=$'\033[1;93m'      # #F9F1A5  15:1
ALERT=$'\033[1;7;93m'   # 反白      15:1  黃底暗字色塊
SECOND=$'\033[0;37m'    # #CCCCCC   9:1  次要脈絡（目錄、行數）
```

（對比值以 Windows Terminal 預設 Campbell 色盤對深色底 `#0C0C0C` 計算。）

配色遵守兩條規則：

**一、平靜狀態不帶色相。** 大部分時間整列都是平靜的，所以它拿到最好讀的顏色（亮白 18:1）；一旦出現任何色相，就代表有東西需要注意。原本的亮藍 `94`（`#3B78FF`，4:1）與亮洋紅 `95`（`#B4009E`，**2.5:1**）是全色盤表現最差的兩個 —— 後者偏偏還是最該被看見的警戒色 —— 已全部移除。

**二、嚴重度沿「明度」升級，不沿「色相」。** 紅綠在 daltonized 設定下無法分辨，所以 WARN 與 ALERT 共用黃色相，靠**反白**區分；反白後 ALERT 反而成為整列對比最高的元素（15:1），任何色覺型態都看得見，警戒層級另外還附加 `!` 標記。

`+A/-R` 兩個數字刻意同色 —— 綠加紅減正是 daltonized 主題分辨不出來的組合。

**淺色主題**請改為：`C_MODEL`→`1;30`（黑）、`CALM`→`0;30`、`C_THINK`→`0;36`、`WARN`→`0;33`、`SECOND`→`0;90`；`ALERT` 的反白 `1;7;33` 在淺色底上依然成立（黃底暗字），不需更動。

---

## 行為細節

**倒數一律無條件捨去** —— 剩 4d5h59m 顯示 `4d5h`，寧可少報也不會讓你以為還有更多時間。單位自動切換：`4d5h` → `2h13m` → `44m` → `<1m`。

**缺資料時整段消失，不顯示空殼**：

| 情況 | 行為 |
|---|---|
| `rate_limits` 不存在（例如用 API key 而非訂閱） | 5h / 7d 兩段都不出現 |
| 只有 `five_hour` | 只顯示 5h |
| `resets_at` 為 null 或已過期 | 只顯示百分比，不顯示倒數 |
| `resets_at` 距今超過 8 天 | 只顯示百分比（最長窗口是 7 天，超過代表時間戳單位不對，不憑空生一個數字） |
| 完全收不到 JSON | 顯示 `Claude │ think:off │ ctx:-- │ $0.00` |
| `version` 鍵不存在 | 不顯示版本前綴 |
| `workspace` 鍵不存在 | 整個目錄區段不出現 |
| 改動行數皆為 0（剛開 session） | 不顯示 `+A/-R` |

**目錄縮寫規則**（末兩層，Windows 與 POSIX 皆適用；`current_dir` 傳來時是 JSON 跳脫的，反斜線會先正規化成斜線）：

| `current_dir` | 顯示 |
|---|---|
| `C:\work\proj\src\components\statusline` | `…/components/statusline` |
| `C:\work\my-project` | `…/work/my-project` |
| `/home/user/work/proj/src/utils` | `…/src/utils` |
| `/home/proj` | `home/proj`（沒東西被截掉就不加 `…/`） |
| `/proj` | `/proj` |
| `/home/user/proj///` | `…/user/proj`（尾端斜線先清掉） |

**訂閱制注意**：`$` 是 API 等值成本，不是實際扣款金額。訂閱額度內不另計費——對 Pro/Max 使用者而言，5h / 7d 那兩段才是真正要看的。

---

## 相容性

只有「重置倒數」依賴系統時鐘，其餘欄位與 bash 版本無關。取時鐘的三層退路：

| bash | 取時鐘方式 | 外部行程 |
|---|---|---|
| 5.0+ | `$EPOCHSECONDS` | 0 |
| 4.2+ | `printf '%(%s)T'` | 0 |
| 3.2（macOS 內建） | `date +%s` | 1 |
| 完全取不到 | 略過倒數，保留百分比 | 0 |

四種情境皆已實測。

**為什麼堅持零外部行程**：狀態列是高頻渲染，而 Windows 上每次 process spawn 要 ~300–640 ms（實測 `awk` 296 ms、`python` 639 ms）。常見的 `jq` 寫法一次渲染要 spawn 7–9 個行程，在 Windows 上會明顯拖慢。

---

## 疑難排解

**狀態列一片空白或只剩分隔線** —— 幾乎都是腳本相依的外部工具不存在。本腳本無此問題（不依賴 `jq`），但若你自行改動請留意。手動測試：

```bash
echo '{"model":{"display_name":"Opus 5"},"cost":{"total_cost_usd":3.41},
"context_window":{"used_percentage":31,"remaining_percentage":69},
"effort":{"level":"xhigh"},"thinking":{"enabled":true}}' | ~/.claude/statusline-command.sh
```

**Windows 上出現 `$'\r': command not found`** —— 檔案被存成 CRLF。轉回 LF：

```bash
sed -i 's/\r$//' ~/.claude/statusline-command.sh
```

**完全沒反應** —— 確認執行權限（`chmod +x`）與 `settings.json` 是合法 JSON（少一個逗號整份設定都會被忽略）。

---

## 完整 payload 結構（供日後擴充）

Claude Code 從 stdin 傳入的 JSON：

```
cwd, model:{id, display_name}, workspace:{current_dir, project_dir}, version,
output_style:{name},
cost:{total_cost_usd, total_duration_ms, total_api_duration_ms,
      total_lines_added, total_lines_removed},
context_window:{total_input_tokens, total_output_tokens, context_window_size,
                current_usage, used_percentage, remaining_percentage},
exceeds_200k_tokens, fast_mode,
effort:{level},            // 僅在模型支援時出現
thinking:{enabled},
rate_limits:{five_hour:{used_percentage, resets_at},
             seven_day:{used_percentage, resets_at}},   // 僅訂閱制
vim:{mode}                 // 僅 vim 模式啟用時
```

`rate_limits.*.used_percentage` 已是 0–100（Claude Code 內部把 0–1 的 utilisation 乘 100），`resets_at` 是 **unix 秒**。

尚未使用、可自行加入的欄位：`fast_mode`、`output_style.name`、`workspace.project_dir`、`cost.total_duration_ms`、`cost.total_api_duration_ms`、`vim.mode`、`exceeds_200k_tokens`（固定 200k 門檻，與 context 大小及計價皆無關）。

> 取 `version` 時錨定在前面的 `,` 或 `{`（`[,{]"version":"`）。單純比對 `"version":"` 會誤中 `"to_version":"` —— 該鍵目前不在狀態列 payload 中，但存在於 CLI 其他地方，加個錨點成本為零。

> 解析採正規式而非完整 JSON parser。取 context 用量時錨定在相鄰的 `remaining_percentage` 鍵，因為 `rate_limits` 也有 `used_percentage`，而只有 `context_window` 後面接著 `remaining_percentage`。不依賴鍵的出現順序。
