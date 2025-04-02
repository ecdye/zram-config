#!/usr/bin/env bash

BASEDIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

check_zram_mounts() {
    while read -r line; do
        case "$line" in
            "#"*)
                # Skip comment line
                continue
                ;;

            "")
                # Skip empty line
                continue
                ;;

            *)
                # shellcheck disable=SC2086
                set -- $line
                ZTYPE="$1"
                TARGET_DIR="$5"
                if [[ $ZTYPE == "swap" ]]; then
                    if [[ "$(swapon | awk '/zram/ { print $1 }' | tr -d '0-9')" != "/dev/zram" ]]; then
                        echo "Test failed: swap not on zram."
                        zramctl --output-all
                        return 1
                    fi
                elif [[ $ZTYPE == "dir" ]] || [[ $ZTYPE == "log" ]]; then
                    if [[ "$(df "$TARGET_DIR" | awk '/overlay/ { print $1 }' | tr -d '0-9')" != "overlay" ]]; then
                        echo "Test failed: overlay for '$TARGET_DIR' not found."
                        zramctl --output-all
                        return 1
                    fi
                fi
                ;;
        esac
    done < "${BASEDIR}/../ztab"
}

check_zram_removal() {
    while read -r line; do
        case "$line" in
            "#"*)
                # Skip comment line
                continue
                ;;

            "")
                # Skip empty line
                continue
                ;;

            *)
                # shellcheck disable=SC2086
                set -- $line
                ZTYPE="$1"
                TARGET_DIR="$5"
                if [[ $ZTYPE == "swap" ]]; then
                    if [[ "$(swapon | awk '/zram/ { print $1 }' | tr -d '0-9')" == "/dev/zram" ]]; then
                        echo "Test failed: swap on zram."
                        zramctl --output-all
                        return 1
                    fi
                elif [[ $ZTYPE == "dir" ]] || [[ $ZTYPE == "log" ]]; then
                    if [[ "$(df "$TARGET_DIR" | awk '/overlay/ { print $1 }' | tr -d '0-9')" == "overlay" ]]; then
                        echo "Test failed: overlay for '$TARGET_DIR' found."
                        zramctl --output-all
                        return 1
                    fi
                fi
                ;;
        esac
    done < "${BASEDIR}/../ztab"
}

if [[ $1 == "removal" ]]; then
    check_zram_removal || exit 1
    test -f /var/log/test || echo "Test failed: /var/log/test not found."
else
    check_zram_mounts || exit 1
fi

# vim: ts=4 sts=4 sw=4 et
