# deploy_agent

Shell automation for the Student Attendance Tracker.
`deploy_agent.sh` deploys the application, runs it, and archives its logs. While it is deploying, it handles Ctrl+C and Ctrl+Z cleanly.

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

