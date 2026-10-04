#!/usr/bin/env bash
# Claude Code status line
#   cwd │ model │ think mode │ context usage │ $ cost + lines │ 5h quota │ 7d quota
#
# Implementation notes:
#   * Pure bash builtins: no jq, awk, bc, date or python. jq is often absent,
#     and on Windows every process spawn costs ~300-640 ms, which a
#     high-frequency status line cannot afford. Zero subprocesses on bash 4.2+
#     (the clock comes from $EPOCHSECONDS / printf %(%s)T).
#   * Portable to bash 3.2 (macOS /bin/bash) - see the clock shim below.
#   * The $ figure is Claude Code's own cost.total_cost_usd, not a guess from
#     hardcoded per-model pricing.
#   * rate_limits.{five_hour,seven_day}.used_percentage is already 0-100
#     (Claude Code multiplies the 0-1 header utilisation by 100); resets_at is
#     a unix timestamp in SECONDS. Either window is absent from the payload
#     when it does not apply, and its segment is then omitted entirely.
#   * Palette targets a DARK, DALTONIZED (colour-blind-safe) theme: severity
#     runs blue -> yellow -> magenta, never green -> red. The alert level also
#     appends '!' so the signal is never colour-alone.

IFS= read -r -d '' input

# ---- thresholds (edit freely) ---------------------------------------------
CTX_WARN=60          # context %, yellow at or above
CTX_ALERT=85         # context %, magenta + '!' at or above
COST_WARN=500        # US cents, yellow at or above  ($5.00)
COST_ALERT=2000      # US cents, magenta at or above ($20.00)
RL_WARN=70           # quota %, yellow at or above
RL_ALERT=90          # quota %, magenta + '!' at or above

# ---- clock shim -----------------------------------------------------------
# $EPOCHSECONDS needs bash 5.0+; printf %(%s)T needs 4.2+. macOS still ships
# bash 3.2, where both are missing and the single `date` fork is the only way.
# Only the reset countdown depends on this - everything else is version-free.
now=${EPOCHSECONDS:-}
if [[ -z $now ]]; then
  printf -v now '%(%s)T' -1 2>/dev/null || now=$(date +%s 2>/dev/null) || now=0
fi

# ---- high-contrast palette ------------------------------------------------
# Tuned against a dark background using the Windows Terminal "Campbell" palette
# (contrast ratios vs #0C0C0C in brackets). Two rules drive the choices:
#   1. CALM carries no hue. Most of the line sits at calm most of the time, so
#      it gets the most readable colour there is, and any hue at all then means
#      "something wants your attention". Bright blue 94 (#3B78FF, 4:1) and
#      bright magenta 95 (#B4009E, 2.5:1) were the two worst performers and are
#      gone entirely.
#   2. Severity escalates along lightness, never along hue. Red/green are
#      indistinguishable on a daltonized setup, so WARN and ALERT share the
#      yellow hue and separate by inversion - which also makes ALERT the
#      highest-contrast element on the whole line.
R=$'\033[0m'
SEP=$'\033[0;90m'            # #767676  4:1   divider only
C_MODEL=$'\033[1;97m'        # #F2F2F2 18:1   identity, boldest
C_THINK=$'\033[1;96m'        # #61D6D6 11:1   the one hue accent while calm
CALM=$'\033[0;97m'           # #F2F2F2 18:1   neutral metrics
WARN=$'\033[1;93m'           # #F9F1A5 15:1
ALERT=$'\033[1;7;93m'        #  reversed 15:1 solid chip, readable under any CVD
SECOND=$'\033[0;37m'         # #CCCCCC  9:1   subordinate context (cwd, lines)

# ---- working directory ----------------------------------------------------
# Last two components only, prefixed with the ellipsis when anything was cut.
# current_dir arrives JSON-escaped, so Windows separators show up as '\\'.
dir=''
re='"current_dir":"([^"]*)"'
if [[ $input =~ $re ]]; then
  raw="${BASH_REMATCH[1]}"
  raw="${raw//\\\\//}"                       # escaped backslash -> slash
  raw="${raw//\\//}"                         # stray backslash   -> slash
  while [[ $raw == */ && ${#raw} -gt 1 ]]; do raw="${raw%/}"; done
  if [[ $raw != */* ]]; then
    dir="$raw"
  else
    last="${raw##*/}"
    parent="${raw%/*}"
    parent="${parent##*/}"
    if [[ -z $parent ]]; then                # path is rooted one level deep
      dir="/$last"
    else
      head="${raw%"$parent/$last"}"
      if [[ -n $head && $head != '/' ]]; then dir="…/$parent/$last"
      else                                    dir="$parent/$last"
      fi
    fi
  fi
fi

# ---- Claude Code version --------------------------------------------------
# This is the CLI's own version, not the model's. Anchored on the preceding
# brace or comma: a bare "version":" would also match "to_version":" if that
# key ever reaches the payload.
ver=''
re='[,{]"version":"([^"]*)"'
[[ $input =~ $re ]] && ver="v${BASH_REMATCH[1]}"

# ---- model name -----------------------------------------------------------
model='Claude'
re='"model":\{[^}]*"display_name":"([^"]*)"'
[[ $input =~ $re ]] && model="${BASH_REMATCH[1]}"

# ---- think mode -----------------------------------------------------------
# effort.level is only present on models that expose reasoning effort;
# otherwise fall back to the thinking on/off flag.
re='"effort":\{"level":"([^"]*)"'
if [[ $input =~ $re ]]; then
  think="think:${BASH_REMATCH[1]}"
elif [[ $input == *'"thinking":{"enabled":true'* ]]; then
  think='think:on'
else
  think='think:off'
fi

# ---- context usage --------------------------------------------------------
# Anchored on the adjacent "remaining_percentage" key: rate_limits also carries
# a "used_percentage", and only context_window is followed by that neighbour.
ctx='ctx:--'
ctx_col=$CALM
re='"used_percentage":([0-9]+)(\.[0-9]+)?,"remaining_percentage"'
if [[ $input =~ $re ]]; then
  pf="${BASH_REMATCH[2]#.}0"
  p=$(( (10#${BASH_REMATCH[1]} * 10 + 10#${pf:0:1} + 5) / 10 ))
  ctx="ctx:${p}%"
  if   (( p >= CTX_ALERT )); then ctx_col=$ALERT; ctx="ctx:${p}%!"
  elif (( p >= CTX_WARN  )); then ctx_col=$WARN
  fi
fi

# ---- real $ cost ----------------------------------------------------------
# Integer-cents arithmetic with half-up rounding; bash has no floating point.
cents=0
re='"total_cost_usd":([0-9]+)(\.([0-9]+))?'
if [[ $input =~ $re ]]; then
  cf="${BASH_REMATCH[3]}000"
  cents=$(( (10#${BASH_REMATCH[1]} * 1000 + 10#${cf:0:3} + 5) / 10 ))
fi
printf -v cost '$%d.%02d' $((cents / 100)) $((cents % 100))
cost_col=$CALM
if   (( cents >= COST_ALERT )); then cost_col=$ALERT
elif (( cents >= COST_WARN  )); then cost_col=$WARN
fi

# ---- lines touched --------------------------------------------------------
# Its own segment. Hidden while nothing has been edited, so a fresh session
# stays uncluttered. One colour for both counts: a +green/-red pair is exactly
# what a daltonized theme cannot distinguish.
lines=''
la=0; lr=0
re='"total_lines_added":([0-9]+)'
[[ $input =~ $re ]] && la=$(( 10#${BASH_REMATCH[1]} ))
re='"total_lines_removed":([0-9]+)'
[[ $input =~ $re ]] && lr=$(( 10#${BASH_REMATCH[1]} ))
(( la > 0 || lr > 0 )) && lines="+${la}/-${lr}"

# ---- rate limit windows ---------------------------------------------------
# Fills rl_seg / rl_col; rl_seg stays empty when the window is not in the
# payload, so the caller can drop the whole segment.
rl_seg=''
rl_col=''
rate_limit_segment() {           # $1 = json key, $2 = display label
  local key="$1" label="$2" re pf p secs dd hh mm
  rl_seg=''
  rl_col=$CALM

  re="\"$key\":\{[^}]*\"used_percentage\":([0-9]+)(\.[0-9]+)?"
  [[ $input =~ $re ]] || return
  pf="${BASH_REMATCH[2]#.}0"
  p=$(( (10#${BASH_REMATCH[1]} * 10 + 10#${pf:0:1} + 5) / 10 ))
  rl_seg="${label}:${p}%"
  if   (( p >= RL_ALERT )); then rl_col=$ALERT; rl_seg="${label}:${p}%!"
  elif (( p >= RL_WARN  )); then rl_col=$WARN
  fi

  # Reset countdown. Bounded at 8 days: the longest window is 7 days, so a
  # larger delta means the timestamp is not what we think it is - show the
  # percentage alone rather than an invented figure.
  re="\"$key\":\{[^}]*\"resets_at\":([0-9]+)"
  [[ $input =~ $re ]] || return
  (( now > 0 )) || return
  secs=$(( 10#${BASH_REMATCH[1]} - now ))
  (( secs > 0 && secs <= 691200 )) || return
  if   (( secs >= 86400 )); then
    dd=$(( secs / 86400 )); hh=$(( (secs % 86400) / 3600 ))
    rl_seg+=" (${dd}d${hh}h)"
  elif (( secs >= 3600 )); then
    hh=$(( secs / 3600 )); mm=$(( (secs % 3600) / 60 ))
    rl_seg+=" (${hh}h${mm}m)"
  elif (( secs >= 60 )); then
    rl_seg+=" ($(( secs / 60 ))m)"
  else
    rl_seg+=" (<1m)"
  fi
}

# ---- render ---------------------------------------------------------------
DIV=" ${SEP}│${R} "
line=''
[[ -n $ver ]] && line="${SECOND}${ver}${R}${DIV}"
line+="${C_MODEL}${model}${R}${DIV}${C_THINK}${think}${R}"
line+="${DIV}${ctx_col}${ctx}${R}"
line+="${DIV}${cost_col}${cost}${R}"
[[ -n $lines ]] && line+="${DIV}${SECOND}${lines}${R}"

rate_limit_segment five_hour 5h
[[ -n $rl_seg ]] && line+="${DIV}${rl_col}${rl_seg}${R}"
rate_limit_segment seven_day 7d
[[ -n $rl_seg ]] && line+="${DIV}${rl_col}${rl_seg}${R}"

# cwd goes last: it is a breadcrumb, not a headline, and trailing it keeps the
# left edge stable so the metrics never shift sideways as you change directory.
[[ -n $dir ]] && line+="${DIV}${SECOND}${dir}${R}"

printf '%s\n' "$line"
