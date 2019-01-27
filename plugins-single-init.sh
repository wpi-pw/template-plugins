#!/bin/bash

# Single Plugins Init - Wp Pro Club
# by DimaMinka (https://dimaminka.com)
# https://github.com/wp-pro-club/init

source ${PWD}/lib/app-init.sh

version=""
zip="^(https|git)(:\/\/|@)([^\/:]+)[\/:]([^\/:]+)\/([^\/:]+)\/([^\/:]+)\/(.+).zip$"
# Get all single plugins and run install by type
for i in "${!conf_app_plugins_single__name[@]}"
do
    printf "${GRN}======================================================${NC}\n"
    printf "${GRN}Installing plugin ${conf_app_plugins_single__name[$i]}${NC}\n"
    printf "${GRN}======================================================${NC}\n"
    # Running plugin install via wp-cli
    if [ "${conf_app_plugins_single__package[$i]}" == "wp-cli" ]; then
        # Install from zip
        if [[ ${conf_app_plugins_single__zip[$i]} =~ $zip ]]; then
            wp plugin install ${conf_app_plugins_single__zip[$i]}
        else
            # Get plugin version from config
            if [ "${conf_app_plugins_single__ver[$i]}" != "*" ]; then
                version="--version=${conf_app_plugins_single__ver[$i]} --force"
            fi
            # Default plugin install via wp-cli
            wp plugin install ${conf_app_plugins_single__name[$i]} ${version}
        fi
    elif [ "${conf_app_plugins_single__package[$i]}" == "wpackagist" ]; then
        # Install plugin from wpackagist via composer
        composer require wpackagist-plugin/${conf_app_plugins_single__name[$i]}:${conf_app_plugins_single__ver[$i]} --update-no-dev
    elif [ "${conf_app_plugins_single__package[$i]}" == "wp-pro-club" ]; then
        ## Install plugin from private bitbacket repository wp-pro-club via composer
        project="${conf_app_plugins_single__package[$i]}/${conf_app_plugins_single__name[$i]}"
        project_ver=${conf_app_plugins_single__ver[$i]}
        project_zip="https://bitbucket.org/$project/get/$project_ver.zip"
        composer config repositories.$project '{"type":"package","package": {"name": "'$project'","version": "'$project_ver'","type": "wordpress-plugin","dist": {"url": "'$project_zip'","type": "zip"}}}'
        composer require $project:$project_ver --update-no-dev
    elif [ "${conf_app_plugins_single__package[$i]}" == "composer" ]; then
        ## Install plugin from private bitbacket repository via composer
        project=${conf_app_plugins_single__name[$i]}
        project_ver=${conf_app_plugins_single__ver[$i]}
        project_zip="https://bitbucket.org/$project/get/$project_ver.zip"
        composer config repositories.$project '{"type":"package","package": {"name": "'$project'","version": "'$project_ver'","type": "wordpress-plugin","dist": {"url": "'$project_zip'","type": "zip"}}}'
        composer require $project:dev-master --update-no-dev
    fi
done
