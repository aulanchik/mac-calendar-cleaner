# Mac-calendar-cleaner

A command-line tool for macOS that finds and batch-deletes events in **Apple Calendar**. It works on any calendar Calendar can show, including an **Outlook / Exchange calendar** that is synced or imported into it.

Typical uses:

- Remove every event whose link points to a certain website (for example old contest reminders).
- Remove all events with a given title (for example `Weekly Sync`) in a date range.
- Preview exactly what would be removed before anything is touched.

**Safe by default:** the script only *lists* matching events. Nothing is deleted unless you add `-d` and then type `DELETE` to confirm.

---

## Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Quick start](#quick-start)
4. [Options](#options)
5. [How matching works](#how-matching-works)
6. [Examples](#examples)
7. [Outlook calendars in Apple Calendar](#outlook-calendars-in-apple-calendar)
8. [Recurring events](#recurring-events)
9. [Backup and restore](#backup-and-restore)
10. [Speed and large calendars](#speed-and-large-calendars)
11. [Troubleshooting](#troubleshooting)
12. [How it works](#how-it-works)
13. [Limitations](#limitations)

---

## Requirements

- **macOS** with the built-in Calendar app. The script uses `osascript` (AppleScript) and BSD `date`, so it does not run on Linux or Windows.
- **Bash.** The version that ships with macOS is fine.
- **Automation permission** for your terminal to control Calendar. macOS asks for it the first time you run the script (see [Troubleshooting](#not-authorized-to-send-apple-events--1743)).

No other software needs to be installed.

## Installation

1. Save `cal-clean.sh` somewhere convenient, for example `~/Scripts/`.
2. Make it executable:

   ```bash
   chmod +x ~/Scripts/cal-clean.sh
   ```

3. If macOS blocks the file because it was downloaded, remove the quarantine flag:

   ```bash
   xattr -d com.apple.quarantine ~/Scripts/cal-clean.sh
   ```

4. Run it from the folder it lives in, or with the full path:

   ```bash
   cd ~/Scripts
   ./cal-clean.sh -h
   ```

## Quick start

**Step 1: find the exact calendar name.**

```bash
./cal-clean.sh -l
```

This prints one calendar name per line. Copy the one you want exactly, including capitalization and spaces. The name must match exactly, and `"Outlook"` will not work unless a calendar really has that name.

**Step 2: preview what would be deleted** (nothing is deleted):

```bash
./cal-clean.sh -c "Calendar" -u "hackerrank.com/contests/" -f 2012-01-01 -t 2018-12-31
```

Example output:

```
Calendar : Calendar
Range    : 2012-01-01 .. 2018-12-31 (inclusive)
Title    : <any>
URL text : hackerrank.com/contests/
Recurring: skipped
----------------------------------------
Searching... (large calendars can take a few minutes; Ctrl+C to stop)
HackerGames | Saturday, 8 September 2012 at 09:00:00
CS Pakistan Contest | Friday, 14 March 2014 at 18:00:00
----------------------------------------
2 event(s) match.
Dry run only. Re-run with -d to delete.
```

**Step 3: delete.** Run the same command again and add `-d`:

```bash
./cal-clean.sh -c "Calendar" -u "hackerrank.com/contests/" -f 2012-01-01 -t 2018-12-31 -d
```

You will see a warning and a prompt. Type `DELETE` (capital letters) and press Return. Anything else cancels and deletes nothing.

Progress is printed live, one line per deleted event:

```
deleted 1 | HackerGames | Saturday, 8 September 2012 at 09:00:00
deleted 2 | CS Pakistan Contest | Friday, 14 March 2014 at 18:00:00
```

## Options

| Option | Meaning | Required? |
|---|---|---|
| `-l` | List calendar names and exit. | no |
| `-c NAME` | Calendar to work on. Exact name, as shown by `-l`. | **yes** |
| `-k TEXT` | Match events whose **title** contains `TEXT`. | no |
| `-u TEXT` | Match events whose **URL, location or notes** contain `TEXT`. | no |
| `-f DATE` | First day to search, `YYYY-MM-DD`, inclusive. Default `2000-01-01`. | no |
| `-t DATE` | Last day to search, `YYYY-MM-DD`, inclusive. Default `2100-12-31`. | no |
| `-r` | Also include **recurring** events. Deleting one removes the whole series. | no |
| `-d` | Actually delete. Without it, the script only previews. | no |
| `-h` | Show help. | no |

**At least one of `-k`, `-u`, `-f` or `-t` must be given.** This stops you from accidentally matching every event in a calendar.

Put values that contain spaces in quotes: `-k "Weekly Sync"`.

## How matching works

An event is selected only if **all** of the filters you gave match:

- **Date range (`-f`, `-t`):** the event's **start date** must fall on or between those days. The event's end date is ignored, so a long event that starts on 8 Sep 2012 and ends in February 2013 is matched by a range that includes 8 Sep 2012. A range that only covers the middle or end of that event will not find it.
- **Title (`-k`):** the title must contain the text. Matching is case-insensitive and partial, so `-k sync` matches `Weekly Sync`.
- **URL text (`-u`):** the text must appear in the event's **URL field, location field or notes**. Some calendar systems store a link in one of these places and some in another. All three are checked, and an event is matched if any one contains the text. Matching is case-insensitive and partial, so you can leave off `https://www.`.
- **`-k` and `-u` together** are combined with AND: the title must match *and* the URL text must match.
- **Recurring events** are skipped unless you pass `-r` (see [below](#recurring-events)).

## Examples

Preview all events titled like "Weekly Sync" in the next two months:

```bash
./cal-clean.sh -c "Calendar" -k "Weekly Sync" -f 2026-11-01 -t 2026-12-31
```

Delete one event by title and its start date (a narrow range is fast):

```bash
./cal-clean.sh -c "Calendar" -k "HackerGames" -f 2012-09-01 -t 2012-09-30 -d
```

Delete every event that links to one specific contest:

```bash
./cal-clean.sh -c "Calendar" -u "hackerrank.com/contests/cspakistan" -f 2010-01-01 -t 2020-12-31 -d
```

Delete every event linking to any contest on that site, one year at a time (easier to watch and faster):

```bash
for year in 2012 2013 2014 2015; do
  ./cal-clean.sh -c "Calendar" -u "hackerrank.com/contests/" -f "$year-01-01" -t "$year-12-31" -d
done
```

Combine title and URL (both must match):

```bash
./cal-clean.sh -c "Calendar" -k "Contest" -u "hackerrank.com" -f 2012-01-01 -t 2016-12-31
```

Include recurring events (be careful, this removes whole series):

```bash
./cal-clean.sh -c "Calendar" -k "Standup" -f 2026-01-01 -t 2026-12-31 -r
```

## Outlook calendars in Apple Calendar

What a delete does depends on **how the Outlook calendar got into Apple Calendar**. In the Calendar sidebar, check which heading the calendar sits under.

| How it was added | Sidebar heading | What the script's delete does |
|---|---|---|
| **Account sync** (Outlook.com, Microsoft 365 or Exchange added in System Settings > Internet Accounts) | Outlook / Exchange | Deletions **sync back to Outlook** and the events disappear there too. |
| **Subscription** (an ICS link) | Subscribed | Events are **read-only**. Apple Calendar cannot delete them, so the delete will fail. Remove them in Outlook, or unsubscribe. |
| **One-time `.ics` import** | iCloud or On My Mac | Only your Apple copy is deleted. Outlook is not changed. |

Things to know for synced Outlook / Exchange calendars:

- Deleting a meeting **you organized** may send cancellation emails to the attendees.
- Deleting a meeting **you were invited to** removes it from your calendar and may decline it.
- Each delete is a separate request to the server, so deleting is slow (see [Speed](#speed-and-large-calendars)).

## Recurring events

A recurring series is a single entry in Calendar, with many occurrences. Deleting it removes **every occurrence**, past and future.

- By default the script **skips** recurring events. In the preview they are not listed.
- With `-r` they are included and marked `[recurring series]` in the preview.
- Calendar matches on the series' **original** start date. A series that started before your `-f` date may not show up even if some of its occurrences fall in your range. If an event is visible in Calendar but missing from the preview, widen the range to include the series' first date.
- If you only want to remove a single occurrence of a series, do that in the Calendar app. This script cannot do it.

## Backup and restore

**Take a backup before deleting.** In Calendar choose **File > Export > Calendar Archive** and save the `.icbarchive` file somewhere safe. To export a single calendar as `.ics`, right-click it in the sidebar and choose **Export...**.

To restore, use **File > Import** in Calendar and pick the archive or `.ics`. Importing adds events. If some of them still exist you may get duplicates, so importing into a new calendar is the cleanest way to check what you had.

Do not rely on `Cmd+Z` after running the script. Deletions made by a script are not reliably undoable, and on a synced calendar they reach the server immediately.

## Speed and large calendars

- **Searching** is fast when you give a date range and slower with the full default range (2000 to 2100) on a calendar with many events. It can still take a minute or more on big calendars.
- **Deleting** is slow because each event is deleted one at a time and, on synced calendars, each delete is sent to the server. A few seconds per event is typical.
- To keep things manageable, delete in **smaller batches** such as one year at a time, as in the loop example above.
- The script prints progress while deleting. If nothing moves for a minute, look in the Calendar app for a dialog that is waiting for an answer.
- You can stop at any time with `Ctrl+C`. Events already deleted stay deleted, and running the same command again continues with what is left.
- For a one-off clean-up of many events, it can be quicker to do it in the Calendar app: press `Cmd+F`, search for the text, press `Cmd+A` to select all results, then press Delete.

## Troubleshooting

### `Calendar not found: NAME (-2700)`

The name given to `-c` does not exactly match a calendar. Run `./cal-clean.sh -l` and copy the name exactly. Watch for capitalization, spaces and look-alike names such as `Calendar` and `Work Calendar`.

### `Not authorized to send Apple events ... (-1743)`

macOS is blocking your terminal from controlling Calendar. Open **System Settings > Privacy & Security > Automation**, find your terminal app (Terminal, iTerm, VS Code and so on), and turn on **Calendar**. Then run the script again. If the entry is missing, reset the prompt with `tccutil reset AppleEvents` and run the script again.

### `No matching events.`

- Check the date range. Remember it is matched against the event's **start** date.
- For `-u`, open one of the events in Calendar and look at where the link is stored (URL, Location or Notes). All three are searched, but the text must really be in the event.
- Shorten the search text. `hackerrank.com/contests` is safer than a full `https://www...` link.
- If the event is recurring, add `-r`.
- Try without the title filter, or with a much wider range, to see whether the filter or the date is the problem.

### The script seems stuck

- Searching a big calendar with the full default date range can take minutes. Add `-f` and `-t`.
- While deleting, check the Calendar app for a prompt dialog.
- Press `Ctrl+C` and retry with a narrower range.

### Lines starting with `FAILED`

The event could not be deleted. The text after the last `|` is the reason from Calendar. Common causes:

- The calendar is a read-only **subscription**. Delete the events at their source.
- You do not have permission to change that event (for example, a shared calendar with view-only access).
- A temporary sync problem. Run the same command again to retry the remaining events.

### `this script needs macOS`

The script uses `osascript` and BSD `date`, which exist only on macOS.

### `-f must look like YYYY-MM-DD`

Dates must be written with four-digit year and two-digit month and day, for example `2012-09-08`.

## How it works

1. The shell script reads your options and checks them. Dates are converted to numbers with BSD `date`.
2. It starts an AppleScript through `osascript` and passes the settings as arguments. Nothing is built by pasting your text into code, so quotes and special characters in titles and URLs are safe.
3. In Calendar, the script asks for events in the chosen calendar whose start date is in the range, and where the title (`-k`) or the URL, location or notes (`-u`) contain your text. Letting Calendar do this filtering is much faster than checking every event one by one.
4. It then skips recurring events (unless `-r`), and either lists the matches (preview) or deletes them (with `-d`). Deleting walks the list from the end to the start so earlier items are not affected by the removals.
5. With `-d`, the script first shows the same preview and the count, then requires you to type `DELETE`. Only after that does it run the delete pass, which repeats the search and removes each match, printing one progress line per event.

## Limitations

- macOS only.
- Matching uses the event **start date**; there is no filter on the end date, organizer or attendees.
- Series that started before `-f` can be missed (see [Recurring events](#recurring-events)).
- Subscribed (ICS) calendars are read-only.
- Deleting a single occurrence of a recurring series is not supported.
- Calendar's scripting interface can be slow and its behavior can vary between macOS versions. Always run the preview first and keep a backup.
