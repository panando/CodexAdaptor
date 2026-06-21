#!/bin/bash
set -euo pipefail

APP_PATH="${1:-CodexAdaptor.app}"

if [ ! -d "${APP_PATH}" ]; then
    echo "ERROR: app bundle not found: ${APP_PATH}" >&2
    exit 1
fi

EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${APP_PATH}/Contents/Info.plist")
BINARY_PATH="${APP_PATH}/Contents/MacOS/${EXECUTABLE}"

if [ ! -x "${BINARY_PATH}" ]; then
    echo "ERROR: app executable not found or not executable: ${BINARY_PATH}" >&2
    exit 1
fi

echo "==> Verifying code signature..."
codesign --verify --deep --strict --verbose=4 "${APP_PATH}"

echo "==> Checking for Xcode library paths..."
if otool -L "${BINARY_PATH}" | grep -q '/Applications/Xcode.app/'; then
    echo "ERROR: executable links against Xcode absolute library paths" >&2
    otool -L "${BINARY_PATH}" | grep '/Applications/Xcode.app/' >&2
    exit 1
fi

if otool -l "${BINARY_PATH}" | grep -q '/Applications/Xcode.app/'; then
    echo "ERROR: executable contains Xcode absolute rpaths" >&2
    otool -l "${BINARY_PATH}" | grep -A2 LC_RPATH >&2
    exit 1
fi

echo "==> Checking Gatekeeper distribution policy..."
set +e
SYSPOLICY_OUTPUT=$(syspolicy_check distribution "${APP_PATH}" 2>&1)
SYSPOLICY_STATUS=$?
set -e

if [ "${SYSPOLICY_STATUS}" -eq 0 ]; then
    echo "Gatekeeper distribution policy accepted."
elif echo "${SYSPOLICY_OUTPUT}" | grep -q 'Notary Ticket Missing' && echo "${SYSPOLICY_OUTPUT}" | grep -q 'Adhoc Signed App'; then
    echo "Gatekeeper rejected this unsigned app as expected: Adhoc Signed App / Notary Ticket Missing."
else
    echo "ERROR: unexpected Gatekeeper distribution failure" >&2
    echo "${SYSPOLICY_OUTPUT}" >&2
    exit 1
fi

echo "Release verification passed: ${APP_PATH}"
