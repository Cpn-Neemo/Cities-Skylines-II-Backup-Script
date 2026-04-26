# TODO List for Cities Skylines II Backup Script

## High Priority
- [ ] Test both scripts in dry-run mode to verify Steam detection and paths
- [ ] Perform actual backup tests on a small dataset
- [ ] Verify compatibility with different Steam installation locations (Snap, custom libraries)
- [ ] Add input validation for configuration variables
- [ ] Improve error handling for missing directories or permissions

## Medium Priority
- [ ] Create a non-silent version of the scripts with verbose output
- [ ] Create a separate configuration file (e.g., config.sh) instead of editing scripts directly
- [ ] Add backup rotation/cleanup functionality to prevent unlimited growth
- [ ] Implement checksum verification for backup integrity
- [ ] Add progress indicators during backup operations
- [ ] Support for multiple backup destinations in a single run

## Low Priority
- [ ] Create a restore script to recover from backups
- [ ] Add email notifications in addition to desktop notifications
- [ ] Implement a simple GUI or web interface for configuration
- [ ] Add support for other backup tools (beyond rsync)
- [ ] Package the scripts as a proper Linux application with installer
- [ ] Add unit tests for critical functions
- [ ] Create comprehensive documentation with screenshots
- [ ] Add security considerations (e.g., SSH key management)
- [ ] Implement backup scheduling within the script (not just cron)
- [ ] Add support for Windows/Mac if possible (though currently Linux-only)

## Documentation
- [ ] Update README with more detailed installation instructions
- [ ] Add troubleshooting section for common issues
- [ ] Create a changelog for version tracking
- [ ] Add examples of cron jobs and automation
- [ ] Document all configuration options thoroughly

## Maintenance
- [ ] Review and update dependencies (rsync, notify-send, etc.)
- [ ] Add issue templates for GitHub
- [ ] Create contributing guidelines
- [ ] Set up basic CI/CD for testing scripts
- [ ] Monitor for Cities: Skylines II updates that might change paths