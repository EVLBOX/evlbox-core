#!/usr/bin/env bats
#
# Tests for the evlbox CLI
#
# Run with:   bats test/
# Install:    sudo apt-get install bats

EVLBOX="./cli/evlbox"

setup() {
    export TEST_DIR="$(mktemp -d)"
    export EVLBOX_STACK_DIR="${TEST_DIR}/stack"
    export EVLBOX_BACKUP_DIR="${TEST_DIR}/backups"
    mkdir -p "$EVLBOX_STACK_DIR" "$EVLBOX_BACKUP_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ─────────────────────────────────
# Help & version (no root/docker)
# ─────────────────────────────────

@test "help shows usage info" {
    run bash "$EVLBOX" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"evlbox"* ]]
}

@test "--help flag works" {
    run bash "$EVLBOX" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "-h flag works" {
    run bash "$EVLBOX" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "version shows semver" {
    run bash "$EVLBOX" version
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "--version flag works" {
    run bash "$EVLBOX" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "no args shows help" {
    run bash "$EVLBOX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "unknown command exits 1" {
    run bash "$EVLBOX" fakecmd
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

@test "help lists all expected commands" {
    run bash "$EVLBOX" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"setup"* ]]
    [[ "$output" == *"update"* ]]
    [[ "$output" == *"backup"* ]]
    [[ "$output" == *"rollback"* ]]
    [[ "$output" == *"restart"* ]]
    [[ "$output" == *"logs"* ]]
    [[ "$output" == *"secure-ssh"* ]]
}

# ─────────────────────────────────
# Guard: missing stack / files
# ─────────────────────────────────

@test "status fails when stack dir is missing" {
    rm -rf "$EVLBOX_STACK_DIR"
    run bash "$EVLBOX" status
    [ "$status" -ne 0 ]
    [[ "$output" == *"No stack found"* ]]
}

@test "status fails when compose.yml is missing" {
    run bash "$EVLBOX" status
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

# ─────────────────────────────────
# Guard: requires root
# ─────────────────────────────────

@test "setup requires root" {
    touch "${EVLBOX_STACK_DIR}/setup.sh"
    run bash "$EVLBOX" setup
    [ "$status" -ne 0 ]
    [[ "$output" == *"root"* ]]
}

@test "update requires root" {
    touch "${EVLBOX_STACK_DIR}/compose.yml"
    run bash "$EVLBOX" update
    [ "$status" -ne 0 ]
    [[ "$output" == *"root"* ]]
}

@test "secure-ssh requires root" {
    run bash "$EVLBOX" secure-ssh
    [ "$status" -ne 0 ]
    [[ "$output" == *"root"* ]]
}

@test "restart requires root" {
    touch "${EVLBOX_STACK_DIR}/compose.yml"
    run bash "$EVLBOX" restart
    [ "$status" -ne 0 ]
    [[ "$output" == *"root"* ]]
}

# ─────────────────────────────────
# Backup list (no root needed)
# ─────────────────────────────────

@test "backup list shows empty when no backups" {
    run bash "$EVLBOX" backup list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No backups"* ]]
}

@test "backup list works when backup dir is missing" {
    rm -rf "$EVLBOX_BACKUP_DIR"
    run bash "$EVLBOX" backup list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No backup directory"* ]]
}
