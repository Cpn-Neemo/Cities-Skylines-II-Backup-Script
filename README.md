🏙️ Cities Skylines II (SC2) Automated Backup Scripts

A set of robust Bash scripts designed to automatically back up your Cities Skylines II save files, maps, mods, and screenshots on Linux. These scripts utilize rsync for efficient, incremental backups and include automatic Steam directory detection.
✨ Features

    🚀 Automatic Detection: Automatically finds your Steam compatdata directory for SC2 (App ID: 949230), supporting standard installs, Snap, and custom library locations.
    🛡️ Safe & Efficient: Uses rsync with --archive, --compress, and --partial flags. Supports Dry-Run mode to test before writing.
    📂 Selective Backups: Backs up critical folders:
        Saves
        Maps
        Screenshots
        Mod Settings & Data
    🔍 Smart Exclusions: Automatically excludes temporary files, caches, and database locks to keep backups clean.
    📝 Detailed Logging: Generates timestamped logs in ~/.backup_logs and copies a summary to your Desktop.
    🔔 Notifications: Sends desktop notifications upon completion (requires libnotify).
    🔄 Dual Modes:
        Remote Version: Backs up to a NAS/Server via SSH.
        Local Version: Backs up to a local directory (USB drive, secondary partition, etc.).

📂 Repository Structure
Script	Description	Best For
BackupScriptRemote.sh	Backs up to a remote server via SSH.	Off-site backups, NAS, VPS.
BackupScriptLocal.sh	Backs up to a local directory.	External HDD, local partition, quick restores.
⚙️ Configuration

Both scripts are configured via variables at the top of the file. Edit these before running.
Common Settings

DRY_RUN="true"          # Set to "false" to perform actual backups
ENABLE_LOGGING="true"   # Set to "false" to disable logging
STEAM_ID=949230         # SC2 App ID (do not change unless using a fork)

Remote Script Specifics (BackupScriptRemote.sh)

REMOTE_USER="your_username"
REMOTE_HOST="192.168.1.50"       # IP or hostname of your server
SSH_KEY="$HOME/.ssh/id_rsa"      # Path to your private SSH key
BACKUP_BASE_REMOTE="~/CS2Backup" # Destination path on the remote server

    Note: Passwordless SSH must be configured for silent operation.

Local Script Specifics (BackupScriptLocal.sh)

BACKUP_BASE_LOCAL="$HOME/CS2Backup" # Change to your desired local path (e.g., "/mnt/backup/SC2")

🚀 Usage
1. Make Executable

chmod +x BackupScriptRemote.sh
chmod +x BackupScriptLocal.sh

2. Test with Dry-Run (Recommended First Step)

Before copying data, run the script with DRY_RUN="true" to see what would happen without making changes.

./BackupScriptLocal.sh
# Or
./BackupScriptRemote.sh

Check the generated log file in ~/.backup_logs or the Desktop log to verify paths.
3. Run Actual Backup

Set DRY_RUN="false" in the script (or pass it as an argument if you modify the script) and run again.

./BackupScriptLocal.sh

4. Automate with Cron

To run the backup daily at 2 AM:

    Open crontab: crontab -e
    Add the following line (adjust paths as needed):

    0 2 * * * /home/youruser/scripts/BackupScriptLocal.sh >> /dev/null 2>&1

🛠️ How It Works

    Detection: The script scans standard Steam paths (~/.steam, ~/.local/share/Steam, /mnt, etc.) and parses libraryfolders.vdf to locate the SC2 compatdata folder.
    Path Construction: It builds the Wine/Proton path: .../compatdata/949230/pfx/drive_c/users/steamuser/AppData/LocalLow/Colossal Order/Cities Skylines II.
    Exclusion: It filters out .cache, *.tmp, and Database/ folders to prevent locking issues and reduce size.
    Transfer: Executes rsync to mirror the source to the destination.
    Reporting: Logs every transferred file and sends a desktop notification.

⚠️ Troubleshooting

    "Source directory does not exist": The script couldn't find your Steam installation. Ensure SC2 is installed and running at least once to generate the folder structure.
    SSH Connection Refused (Remote): Ensure your SSH key is added to the remote server's authorized_keys and that StrictHostKeyChecking is accepted.
    Permission Denied: Ensure the script has execute permissions (chmod +x) and that you have write access to the BACKUP_BASE directory.
    Notifications Not Showing: Install libnotify-bin (Debian/Ubuntu) or libnotify (Arch/Fedora).

📜 License

This project is shared for educational and utility purposes. Feel free to modify and distribute.
🤝 Contributing

Found a bug or have a suggestion? Open an issue or submit a pull request!

Created by Neemo
