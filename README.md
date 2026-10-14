# deploy_agent

Shell automation for the Student Attendance Tracker.
`deploy_agent.sh` deploys the application, runs it, and archives its logs. While it is deploying, it handles Ctrl+C and Ctrl+Z cleanly.

A demonstration of the project: https://youtu.be/mr0-39RCNO4?si=J_I1S27OqBoa9B50

## Repository layout

```
deploy_agent_BryanBen92/
├── deploy_agent.sh
├── README.md
├── .gitignore
└── templates/
    ├── attendance_checker.py
    ├── assets.csv
    └── config.json
```

The three files in `templates/` are the original source files, unmodified.

## What a deployed project looks like

`reports/` starts empty. The application creates the logs there. `archives/` appears after the first archive run.

```
attendance_tracker_<name>/
├── attendance_checker.py
├── Helpers/
│   ├── assets.csv
│   └── config.json
├── reports/
│   ├── attendance.log
│   └── absent.log
└── archives/
    ├── attendance/attendance_YYYYMMDD_HHMMSS.log
    └── absent/absent_YYYYMMDD_HHMMSS.log
```

## Requirements

`bash`, `python3` and `zip`. Tested on an Ubuntu server with Python 3.8.10.

## How to run

```bash
git clone https://github.com/BryanBen92/deploy_agent_BryanBen92.git
cd deploy_agent_BryanBen92
chmod +x deploy_agent.sh
./deploy_agent.sh
```

### How to select a feature

The script has an interactive menu:

```
1) Deploy a new project
2) Run the application on a deployed project
3) Archive logs of a deployed project
4) Exit
```

Each feature can also be started directly with an argument:

```bash
./deploy_agent.sh deploy
./deploy_agent.sh run
./deploy_agent.sh archive
```

## Feature 1: Deploy

1. **Pre-flight checks.** The script checks that `python3` and `zip` are installed, runs `python3 --version`, and checks that the three template files exist. If anything is missing it stops with a clear message.
2. **Project name.** It asks for a name (letters, digits, `_` and `-` only) and creates `attendance_tracker_<name>/`.
   If that directory already exists, it asks whether to overwrite. The old copy is moved aside and only deleted after the new deployment succeeds. If the deployment fails or is interrupted, the old copy is restored. Answering no aborts and changes nothing.
3. **Files.** `attendance_checker.py` and `config.json` are copied unmodified from `templates/`.
4. **Roster.** You choose how `Helpers/assets.csv` is built:
   - **Option A, copy from the template:** asks how many students (1 up to the number in the template) and copies the header plus that many rows. The sample rows each have 4 prior sessions.
   - **Option B, generate a fresh roster:** asks how many students (1 to 100) and builds the rows inside the script from arrays of sample first and last names. Both counts start at 0.
5. **total_sessions stays consistent with the roster.** The rule is `total_sessions = prior sessions in the roster + 1 (today)`.
   - Option A keeps `"total_sessions": 5` (4 prior sessions + today).
   - Option B changes it to `1` with `sed`, because a fresh roster means this is the first session.
6. **Permissions.** `attendance_checker.py` gets `chmod +x`. `Helpers/config.json` gets `chmod 600` (owner read/write only) because it controls the grading thresholds. The script prints the resulting permissions.
7. **Threshold update (optional).** The script asks whether to update the alert thresholds. If yes, it asks for `warning` (default 75) and `failure` (default 50).
   - Pressing Enter keeps the default.
   - The input is checked **before** `sed` runs. Only whole numbers from 0 to 100 are accepted. Anything else (empty text, letters, negative numbers, decimals) is rejected and asked again.
   - The warning value must be higher than the failure value.
   - `sed` then edits only the `"warning": <number>` and `"failure": <number>` lines in place, so the rest of the file is not reformatted or reordered. The updated lines are printed back.
8. **Verification.** The deploy ends by running the application (Feature 2). If the app starts and reads its roster and config, the script reports that verification passed.

## Feature 2: Run

The script lists the deployed projects in the current folder. You pick one by number or by name, and it runs:

```bash
cd attendance_tracker_<name>
python3 attendance_checker.py
```

The app is interactive: you mark each student present (`P`) or absent (`A`).

## Feature 3: Archive logs

The script lists the deployed projects, you pick one, and then it checks `reports/attendance.log` and `reports/absent.log`.

- Each log that exists is **copied** into its own folder with a timestamp in the name:
  - `reports/attendance.log` becomes `archives/attendance/attendance_YYYYMMDD_HHMMSS.log`
  - `reports/absent.log` becomes `archives/absent/absent_YYYYMMDD_HHMMSS.log`
- If a log does not exist (for example nobody was absent, so no `absent.log` was created), the script reports that it was skipped and carries on without crashing.
- At the end it prints which logs were archived and their final paths, for example `Done: 2 archived, 0 skipped.`
- Logs are copied, not moved, because the app appends to them every session, so `reports/` keeps the full history.
- An archive is never overwritten. If two archives get the same timestamp, `_1`, `_2` and so on is added to the name.

## Ctrl+C and Ctrl+Z during deployment

The script traps `SIGINT` (Ctrl+C) and `SIGTSTP` (Ctrl+Z) for the whole deploy feature. The traps are removed before the Python app starts, so they only protect the shell script and not the marking session.

When either signal arrives, the script:

1. prints that the deployment was interrupted,
2. zips whatever exists of `attendance_tracker_<name>/` into `attendance_tracker_<name>_archive.zip`,
3. deletes the incomplete directory so no half-made project is left behind (it only does this after the zip succeeded, so work is never lost),
4. restores your previous project if you were overwriting one,
5. exits cleanly with status 130.

If you interrupt before anything was created (for example at the project name prompt), it says there is nothing to archive and creates no zip.

### How to test it

```bash
./deploy_agent.sh deploy
```

Enter a name such as `sigtest`, choose `A`, enter `4`, answer `y` to the threshold question, then press **Ctrl+C** (or **Ctrl+Z**) at the "New warning threshold" prompt. Then check:

```bash
ls
unzip -l attendance_tracker_sigtest_archive.zip
```

`ls` shows the `.zip` file but no `attendance_tracker_sigtest/` folder.

### What the .zip contains

It contains the project as it was at the moment of the interrupt. Interrupting at the threshold prompt gives:

- `attendance_checker.py`
- `Helpers/config.json`
- `Helpers/assets.csv`
- the empty `reports/` folder

Interrupting earlier gives a smaller zip.

## Testing

Run these from the repository folder.

**Deployed structure and permissions**

```bash
./deploy_agent.sh deploy
find attendance_tracker_<name>
ls -l attendance_tracker_<name>/attendance_checker.py attendance_tracker_<name>/Helpers/config.json
```

Expected: `attendance_checker.py`, `Helpers/assets.csv`, `Helpers/config.json` and `reports/` exist. The app shows `-rwxr-xr-x` and `config.json` shows `-rw-------`.

**Roster and total_sessions**

- Option A: `Helpers/assets.csv` has the header plus the number of rows you asked for, and `total_sessions` is 5.
- Option B: all counts are 0, every email is unique, and `total_sessions` is 1.

```bash
cat attendance_tracker_<name>/Helpers/assets.csv
grep total_sessions attendance_tracker_<name>/Helpers/config.json
```

**Threshold update and input validation**

Answer `y`, then try empty input, letters, `150` and a warning lower than the failure value. Each should be rejected and asked again. After valid values, only the `warning` and `failure` lines change in `Helpers/config.json`.

**Existing directory**

Deploy the same name twice. Answering `n` aborts with nothing changed. Answering `y` replaces the project.

**Archive**

```bash
./deploy_agent.sh archive
find attendance_tracker_<name>/archives
```

Expected: one timestamped file in `archives/attendance/` and one in `archives/absent/`. If nobody was marked absent, the script reports that `absent.log` was skipped.

**Missing tools**

If `zip` or `python3` is not installed, the pre-flight check stops with a clear message before anything is created.

## Notes

- Each run of the application is one session. Running Feature 2 again on the same project adds another session, so `total_sessions` in `Helpers/config.json` would need to be raised by 1 first, otherwise the app prints a note that the prior session count does not match and percentages can go above 100%.
- Generated projects, archives and zip files are listed in `.gitignore` so they are not committed.

