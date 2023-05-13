#!/usr/bin/env zsh

# Settings
readonly DEBUG=false

# Colours
readonly RESET="\e[0m"
readonly RED="\e[0;91m"
readonly GREEN="\e[0;92m"
readonly YELLOW="\e[0;93m"
readonly CYAN="\e[0;96m"

confirmation() {
    local message="${1}"
    if [[ -z "$message" ]]; then
        echo -e "${RED}Message cannot be blank${RESET}"
        exit 1
    fi

    local default="${2}"
    if [[ -z "$default" ]]; then
        local options="Y/N"
    elif [[ "$default" == false ]]; then
        local options="y/N"
    elif [[ "$default" == true ]]; then
        local options="Y/n"
    else
        echo -e "${RED}Default must be a boolean${RESET}"
        exit 1
    fi

    while true; do
        echo -ne "${CYAN}${message}${CYAN} (${options})${RESET}? "
        read result
        if [[ -z "$result" ]] && [[ -n "$default" ]]; then
            result=$default
            return 0
        fi

        if [[ "$result" == false ]] || [[ "$result" == true ]]; then
            return 0
        fi

        result="${result:0:1:l}"
        if [[ "$result" == "n" ]]; then
            result=false
            return 0
        fi

        if [[ "$result" == "y" ]]; then
            result=true
            return 0
        fi
    done
}

input() {
    local message="${1}"
    if [[ -z "$message" ]]; then
        echo -e "${RED}Message cannot be blank${RESET}"
        exit 1
    fi

    local optional="${2:-false}"
    if [[ "$optional" != false ]] && [[ "$optional" != true ]]; then
        echo -e "${RED}Optional must be a boolean${RESET}"
        exit 1
    fi

    while true; do
        echo -ne "${CYAN}${message}${RESET}: "
        read result
        if [[ -n "$result" ]] || [[ "$optional" == true ]]; then
            return 0
        fi
    done
}

pause() {
    echo -ne "${CYAN}Press any key to continue...${RESET}"
    read -k 1 -s
    echo ""
    return 0
}

check_pod() {
    local result
    result=$(pod --version 2>&1)
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}CocoaPods is not installed!${RESET}"
        echo -e "Homebrew: ${CYAN}https://formulae.brew.sh/formula/cocoapods${RESET}"
        echo -e "Website:  ${CYAN}https://cocoapods.org/${RESET}"
        echo ""
        exit 1
    elif [[ "$DEBUG" == true ]]; then
        echo -e "${GREEN}CocoaPods v${result}${RESET}"
    fi
}

get_team_id() {
    local result
    result=$(security find-identity -p codesigning -v 2>&1)
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Encountered an error while finding identities${RESET}"
        if [[ "$DEBUG" == true ]]; then
            echo "${result}"
        fi

        return 1
    fi

    local identities=()
    while IFS= read -r line; do
        if [[ "$line" =~ "\"(.+)\"$" ]]; then
            identities+=("${match[1]}")
        elif [[ "$DEBUG" == true ]]; then
            echo -e "${YELLOW}Failed to parse${RESET}: ${line}"
        fi
    done <<< "$result"

    if [[ ${#identities[@]} -eq 0 ]]; then
        if [[ "$DEBUG" == true ]]; then
            echo -e "${YELLOW}No identities found${RESET}"
        fi

        return 1
    fi

    local team_ids=()
    local team_names=()
    for identity in "${identities[@]}"; do
        result=$(security find-certificate -c "$identity" -p 2>&1)
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Encountered an error while finding certificate${RESET}: \"${identity}\""
            if [[ "$DEBUG" == true ]]; then
                echo "${result}"
            fi

            continue
        fi

        result=$(echo "${result}" | openssl x509 -noout -subject 2>&1)
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Encountered an error while parsing certificate${RESET}: \"${identity}\""
            if [[ "$DEBUG" == true ]]; then
                echo "${result}"
            fi

            continue
        fi

        if [[ "$result" =~ "\/OU=([^\/]+)\/O=([^\/]+)" ]]; then
            team_ids+=("${match[1]}")
            team_names+=("${match[2]}")
        elif [[ "$DEBUG" == true ]]; then
            echo -e "${YELLOW}Failed to parse${RESET}: ${result}"
        fi
    done

    if [[ ${#team_ids[@]} -ne ${#team_names[@]} ]]; then
        echo -e "${RED}Mismatched Team Arrays${RESET}"
        return 1
    fi

    if [[ ${#team_ids[@]} -eq 0 ]]; then
        if [[ "$DEBUG" == true ]]; then
            echo -e "${YELLOW}No teams found${RESET}"
        fi

        return 1
    fi

    if [[ ${#team_ids[@]} -eq 1 ]]; then
        confirmation "Confirm Team ${RESET}${team_ids[1]} (${team_names[1]})" true
        if [[ "$result" == true ]]; then
            team_id="${team_ids[1]}"
            return 0
        fi

        return 1
    fi

    echo -e "${CYAN}Available Teams${RESET}:"
    for (( index=1; index<=${#team_ids[@]}; index++ )); do
        echo "  ${team_ids[$index]} (${team_names[$index]})"
    done

    while true; do
        input "Enter Team Id"
        team_id="${result}"
        if (( ! $team_ids[(Ie)$team_id] )); then
            confirmation "${YELLOW}Team \"${team_id}\" is unavailable, Continue anyway" true
            if [[ "$result" == false ]]; then
                continue
            fi
        fi

        return 0
    done
}

get_server_id() {
    preference_path=~/Library/Preferences/com.rileytestut.AltServer.plist
    if [[ ! -f "$preference_path" ]]; then
        echo -e "${YELLOW}AltServer preferences not found${RESET}"
        return 1
    fi

    local result
    result=$(plutil -extract serverID raw -o - "$preference_path" 2>&1)
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Encountered an error while parsing preferences${RESET}"
        if [[ "$DEBUG" == true ]]; then
            echo "${result}"
        fi

        return 1
    fi

    if [[ -z "$result" ]]; then
        return 1
    fi

    server_id="$result"
    confirmation "Confirm Server ${RESET}${server_id}" true
    if [[ "$result" == false ]]; then
        return 1
    fi

    return 0
}

check_pod

input "Enter Identifier Prefix"
old_identifier_prefix="com.rileytestut."
if [[ "$result" =~ ".+\.$" ]]; then
    new_identifier_prefix="$result"
else
    new_identifier_prefix="${result}."
fi

old_team_id="6XVY5G3U44"
if get_team_id; then
    new_team_id="$team_id"
else
    input "Enter Team Id"
    new_team_id="$result"
fi

input "Enter Device Id"
old_device_id="00008110-000A68390A82801E"
new_device_id="$result"

old_server_id="1F7D5B55-79CE-4546-A029-D4DDC4AF3B6D"
if get_server_id; then
    new_server_id="$server_id"
else
    input "Enter Server Id"
    new_server_id="$result"
fi

echo ""
echo -e "${CYAN}Overview${RESET}:"
echo -e "- ${CYAN}Identifier${RESET}: ${old_identifier_prefix}${CYAN} -> ${RESET}${new_identifier_prefix}"
echo -e "- ${CYAN}Team Id${RESET}: ${old_team_id}${CYAN} -> ${RESET}${new_team_id}"
echo -e "- ${CYAN}Device Id${RESET}: ${old_device_id}${CYAN} -> ${RESET}${new_device_id}"
echo -e "- ${CYAN}Server Id${RESET}: ${old_server_id}${CYAN} -> ${RESET}${new_server_id}"
echo ""

pause

git clone https://github.com/altstoreio/AltStore.git
if [[ $? -ne 0 ]]; then
   exit 1
fi

cd AltStore
if [[ $? -ne 0 ]]; then
   exit 1
fi

git checkout develop
if [[ $? -ne 0 ]]; then
   exit 1
fi

git submodule update --init --recursive
if [[ $? -ne 0 ]]; then
   exit 1
fi

sed -i '' -e "s/${old_identifier_prefix}AltStore;/${new_identifier_prefix}AltStore;/g" \
    AltStore.xcodeproj/project.pbxproj

sed -i '' -e "s/${old_identifier_prefix}AltStore.AltWidget;/${new_identifier_prefix}AltStore.AltWidget;/g" \
    AltStore.xcodeproj/project.pbxproj

sed -i '' -e "s/group.${old_identifier_prefix}/group.${new_identifier_prefix}/g" \
    AltBackup/AltBackup.entitlements \
    AltBackup/Info.plist \
    AltStore/AltStore.entitlements \
    AltStore/Info.plist \
    AltWidget/AltWidgetExtension.entitlements \
    AltWidget/Info.plist \
    Shared/Extensions/Bundle+AltStore.swift

sed -i '' -e "s/${old_team_id}/${new_team_id}/g" \
    AltDaemon/AltDaemon.entitlements \
    AltStore.xcodeproj/project.pbxproj

sed -i '' -e "s/${old_device_id}/${new_device_id}/g" \
    AltStore/Info.plist

sed -i '' -e "s/${old_server_id}/${new_server_id}/g" \
    AltStore/Info.plist

echo ""
echo -e "${GREEN}Success${RESET}"
echo ""