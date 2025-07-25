#!/bin/bash

#########################################################
#
#    File: /crons/security-kit
#    Author: Truc Minh Phan <immersedone>
#    Last Modified: Truc Minh Phan (03/02/2020)
#    Description:
#
#    This file is contains the BASH Script commands
#    that are called upon via cron task.
#
#    Invoking User: `shadower`
#    Cron Timing: `weekly`
#
#########################################################


# SECURITY #1: ClamAV (Anti-virus)

## Home Directories
clamscan -r -i /home/ >> /var/logs/bashmin/security/clamav/clamav-home-report.log; mv /var/logs/bashmin/security/clamav/clamav-home-report.log /var/logs/bashmin/security/clamav/clamav-home-report-`date +"%d-%m-%Y"`.log

## Web Directories
clamscan -r -i /var/www/ >> /var/logs/bashmin/security/clamav/clamav-www-report.log; mv /var/logs/bashmin/security/clamav/clamav-www-report.log /var/logs/bashmin/security/clamav/clamav-www-report-`date +"%d-%m-%Y"`.log


# SECURITY #2: RKHunter (Root-kit Detector)
rkhunter --check --report-warnings-only >> /var/logs/bashmin/security/rkhunter/rkhunter-report.log; mv /var/logs/bashmin/security/rkhunter/rkhunter-report.log /var/logs/bashmin/security/rkhunter/rkhunter-report-`date +"%d-%m-%Y"`.log

# SECURITY #3: Lynis (System Auditing)
lynis audit system >> /var/logs/bashmin/security/lynis/lynis-report.log; mv /var/logs/bashmin/security/lynis/lynis-report.log /var/logs/bashmin/security/lynis/lynis-report-`date +"%d-%m-%Y"`.log
