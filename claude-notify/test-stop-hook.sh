#!/bin/bash
# Minimal Stop hook test — writes to /tmp to verify hook execution
echo "[$(date '+%H:%M:%S')] Stop hook fired. PID=$$ PPID=$PPID" >> /tmp/claude-stop-test.log
cat >> /tmp/claude-stop-test.log  # dump stdin
echo "" >> /tmp/claude-stop-test.log
