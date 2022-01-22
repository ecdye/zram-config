#!/usr/bin/env bash

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
          if [[ "$(swapon | grep -q zram)" ]]; then
            echo "Test failed: swap not on zram."
            return 1
          fi
        elif [[ $ZTYPE == "dir" ]] || [[ $ZTYPE == "log" ]]; then
          if [[ "$(df "$TARGET_DIR" | awk '/overlay/ { print $1 }' | tr -d '0-9')" != "overlay" ]]; then
            echo "Test failed: overlay for '$TARGET_DIR' not found."
            return 1
          fi
        fi
        ;;
    esac
  done < /etc/ztab
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
          if ! [[ "$(swapon | grep -q zram)" ]]; then
            echo "Test failed: swap on zram."
            return 1
          fi
        elif [[ $ZTYPE == "dir" ]] || [[ $ZTYPE == "log" ]]; then
          if ! [[ "$(df "$TARGET_DIR" | awk '/overlay/ { print $1 }' | tr -d '0-9')" != "overlay" ]]; then
            echo "Test failed: overlay for '$TARGET_DIR' found."
            return 1
          fi
        fi
        ;;
    esac
  done < /etc/ztab
}

if [[ $1 == "removal" ]]; then
  check_zram_removal || exit 1
else
  check_zram_mounts || exit 1
fi
