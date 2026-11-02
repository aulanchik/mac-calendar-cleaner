#!/usr/bin/env bash
#
# macos-calendar-cleaner.sh - preview and batch-delete events in Apple Calendar (macOS).
#
# Run ./mac-calendar-cleaner.sh -h for usage, or read README.md for the full guide.

set -euo pipefail

readonly DEFAULT_FROM="2000-01-01"
readonly DEFAULT_TO="2100-12-31"
readonly CONFIRM_WORD="DELETE"
readonly RULE="----------------------------------------"

# Settings, filled in from the command-line options.
CAL=""
KEYWORD=""
URL_TEXT=""
FROM=""
TO=""
INCLUDE_RECURRING="no"
DO_DELETE=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
mac-calendar-cleaner.sh - preview and batch-delete events in Apple Calendar (macOS).

By default this is a DRY RUN: it only lists what would be deleted.
Add -d to really delete (you will be asked to type $CONFIRM_WORD first).

Usage:
  ./mac-calendar-cleaner.sh -l
  ./mac-calendar-cleaner.sh -c CALENDAR [filters] [-r] [-d]

Options:
  -l         list calendar names and exit
  -c NAME    calendar name (required, exact match)
  -k TEXT    only events whose title contains TEXT (case-insensitive)
  -u TEXT    only events whose URL, location or notes contain TEXT
             (case-insensitive; combined with -k as AND)
  -f DATE    first day to search, YYYY-MM-DD (inclusive; default $DEFAULT_FROM)
  -t DATE    last day to search, YYYY-MM-DD (inclusive; default $DEFAULT_TO)
  -r         also include recurring events (deleting one removes the WHOLE series)
  -d         actually delete (default is preview only)
  -h         show this help

At least one of -k, -u, -f or -t must be given.

Examples:
  ./mac-calendar-cleaner.sh -c "Calendar" -k "Weekly Sync" -f 2026-11-01 -t 2026-12-31
  ./mac-calendar-cleaner.sh -c "Calendar" -u "hackerrank.com/contests/" -f 2012-01-01 -t 2018-12-31
  ./mac-calendar-cleaner.sh -c "Calendar" -u "hackerrank.com/contests/" -f 2012-01-01 -t 2018-12-31 -d
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

usage_error() {
  echo "Error: $*" >&2
  echo >&2
  usage >&2
  exit 1
}

require_macos() {
  [[ "$(uname)" == "Darwin" ]] || die "this script needs macOS (it uses osascript and BSD date)."
}

# Print "YYYY MM DD" for a YYYY-MM-DD string, or stop with an error.
split_date() {
  local label="$1" value="$2"
  [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
    || die "$label must look like YYYY-MM-DD (got: $value)"
  date -j -f "%Y-%m-%d" "$value" "+%Y %m %d" 2>/dev/null \
    || die "$label is not a valid date: $value"
}

# ---------------------------------------------------------------------------
# Calendar access (AppleScript)
# ---------------------------------------------------------------------------

list_calendars() {
  osascript <<'AS'
tell application "Calendar"
  set out to ""
  repeat with c in calendars
    set out to out & (name of c) & linefeed
  end repeat
  return out
end tell
AS
}

# run_calendar_script preview|delete
#   preview: prints one "title | start date" line per matching event.
#   delete:  deletes the matching events, logging progress live to stderr;
#            prints only the events that failed to delete.
run_calendar_script() {
  local mode="$1"
  osascript - "$CAL" "$KEYWORD" "$Y1" "$M1" "$D1" "$Y2" "$M2" "$D2" \
    "$INCLUDE_RECURRING" "$mode" "$URL_TEXT" <<'AS'
-- Build a date at midnight from numeric parts.
on makeDate(y, m, d)
  set dt to current date
  set day of dt to 1 -- avoid overflow while changing month
  set year of dt to y
  set month of dt to m
  set day of dt to d
  set time of dt to 0
  return dt
end makeDate

on run argv
  set calName to item 1 of argv
  set titleText to item 2 of argv
  set startD to my makeDate((item 3 of argv) as integer, (item 4 of argv) as integer, (item 5 of argv) as integer)
  -- End of the last day: midnight of the day after -t.
  set endD to (my makeDate((item 6 of argv) as integer, (item 7 of argv) as integer, (item 8 of argv) as integer)) + (1 * days)
  set includeRecurring to (item 9 of argv) is "yes"
  set mode to item 10 of argv
  set urlText to item 11 of argv

  set failures to ""
  set listing to ""
  set n to 0

  tell application "Calendar"
    if not (exists calendar calName) then error "Calendar not found: " & calName
    tell calendar calName

      -- Step 1: let Calendar do the filtering (much faster than checking
      -- every event ourselves).
      if urlText is "" then
        if titleText is "" then
          set candidates to (every event whose start date >= startD and start date < endD)
        else
          set candidates to (every event whose start date >= startD and start date < endD and summary contains titleText)
        end if
      else
        -- URL text can live in the URL, location or notes field: query each
        -- field separately, then merge the results without duplicates.
        set byLocation to {}
        set byUrl to {}
        set byNotes to {}
        try
          set byLocation to (every event whose start date >= startD and start date < endD and location contains urlText)
        end try
        try
          set byUrl to (every event whose start date >= startD and start date < endD and url contains urlText)
        end try
        try
          set byNotes to (every event whose start date >= startD and start date < endD and description contains urlText)
        end try
        set candidates to {}
        set seenUids to {}
        repeat with grp in {byLocation, byUrl, byNotes}
          repeat with x in (contents of grp)
            set uidValue to uid of x
            if seenUids does not contain uidValue then
              set end of seenUids to uidValue
              set end of candidates to (contents of x)
            end if
          end repeat
        end repeat
      end if

      -- Step 2: apply the remaining checks, then list or delete.
      -- Walk backwards so deleting does not disturb the items still to visit.
      repeat with i from (count of candidates) to 1 by -1
        set ev to item i of candidates

        set isRecurring to false
        try
          set r to recurrence of ev
          if r is not missing value and r is not "" then set isRecurring to true
        end try

        -- With -u the title filter was not applied yet, so do it here.
        set titleOK to true
        if urlText is not "" and titleText is not "" then
          if not ((summary of ev) contains titleText) then set titleOK to false
        end if

        if (includeRecurring or not isRecurring) and titleOK then
          set evTitle to summary of ev
          set evStart to (start date of ev) as string
          set tag to ""
          if isRecurring then set tag to " [recurring series]"

          if mode is "delete" then
            try
              delete ev
              set n to n + 1
              log "deleted " & n & " | " & evTitle & " | " & evStart & tag
            on error errMsg
              log "FAILED | " & evTitle & " | " & evStart & " | " & errMsg
              set failures to failures & "FAILED  | " & evTitle & " | " & evStart & " | " & errMsg & linefeed
            end try
          else
            set listing to listing & evTitle & " | " & evStart & tag & linefeed
          end if
        end if
      end repeat
    end tell
  end tell

  if mode is "delete" then return failures
  return listing
end run
AS
}

# ---------------------------------------------------------------------------
# Argument handling
# ---------------------------------------------------------------------------

parse_args() {
  local opt
  while getopts ":c:k:u:f:t:drlh" opt; do
    case "$opt" in
      c) CAL=$OPTARG ;;
      k) KEYWORD=$OPTARG ;;
      u) URL_TEXT=$OPTARG ;;
      f) FROM=$OPTARG ;;
      t) TO=$OPTARG ;;
      r) INCLUDE_RECURRING="yes" ;;
      d) DO_DELETE=1 ;;
      l) require_macos; list_calendars; exit 0 ;;
      h) usage; exit 0 ;;
      \?) usage_error "unknown option: -$OPTARG" ;;
      :)  usage_error "option -$OPTARG needs a value" ;;
    esac
  done
}

validate_args() {
  [[ -n "$CAL" ]] || usage_error "-c (calendar name) is required. Use -l to list calendars."
  [[ -n "$KEYWORD$URL_TEXT$FROM$TO" ]] || usage_error "give at least one filter: -k, -u, -f or -t."

  FROM="${FROM:-$DEFAULT_FROM}"
  TO="${TO:-$DEFAULT_TO}"

  local from_parts to_parts
  from_parts="$(split_date "-f" "$FROM")"
  to_parts="$(split_date "-t" "$TO")"
  read -r Y1 M1 D1 <<<"$from_parts"
  read -r Y2 M2 D2 <<<"$to_parts"

  [[ ! "$FROM" > "$TO" ]] || die "-f ($FROM) is after -t ($TO)."
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

print_settings() {
  echo "Calendar : $CAL"
  echo "Range    : $FROM .. $TO (inclusive)"
  echo "Title    : ${KEYWORD:-<any>}"
  echo "URL text : ${URL_TEXT:-<any>}"
  echo "Recurring: $([[ "$INCLUDE_RECURRING" == "yes" ]] && echo included || echo skipped)"
  echo "$RULE"
}

confirm_delete() {
  cat <<EOF

WARNING: on a synced Outlook/Exchange calendar this deletes the events in
Outlook too, and may send cancellations to attendees of meetings you organized.
Tip: Calendar > File > Export > Calendar Archive gives you a backup first.
EOF
  local answer
  read -r -p "Type $CONFIRM_WORD to continue: " answer
  [[ "$answer" == "$CONFIRM_WORD" ]] || { echo "Aborted. Nothing was deleted."; exit 1; }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  parse_args "$@"
  validate_args
  require_macos

  print_settings
  echo "Searching... (large calendars can take a few minutes; Ctrl+C to stop)"

  local preview count
  preview="$(run_calendar_script preview)"
  count="$(printf '%s' "$preview" | grep -c . || true)"

  if [[ "$count" -eq 0 ]]; then
    echo "No matching events."
    exit 0
  fi

  printf '%s\n' "$preview"
  echo "$RULE"
  echo "$count event(s) match."

  if [[ "$DO_DELETE" -ne 1 ]]; then
    echo "Dry run only. Re-run with -d to delete."
    exit 0
  fi

  confirm_delete

  echo "Deleting $count event(s)... each one can take a few seconds on a synced calendar."
  echo "(Progress is printed below. If nothing moves, check Calendar for a prompt dialog.)"
  local failures
  failures="$(run_calendar_script delete)"
  if [[ -n "$failures" ]]; then
    echo "$RULE"
    echo "Some events could not be deleted:"
    printf '%s\n' "$failures"
  fi
  echo "Done."
}

main "$@"
