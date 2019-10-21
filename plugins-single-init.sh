#!/bin/bash

# WPI Single Plugins
# by DimaMinka (https://dima.mk)
# https://github.com/wpi-pw/app

# Get config files and put to array
wpi_confs=()
for ymls in wpi-config/*
do
  wpi_confs+=("$ymls")
done

# Get wpi-source for yml parsing, noroot, errors etc
source <(curl -s https://raw.githubusercontent.com/wpi-pw/template-workflow/master/wpi-source.sh)

cur_env=$1
version=""
zip="^(https|git)(:\/\/|@)([^\/:]+)[\/:]([^\/:]+)\/([^\/:]+)\/([^\/:]+)\/(.+).zip$"
# Get all single plugins and run install by type
for i in "${!wpi_plugins_single__name[@]}"
do
  printf "${GRN}=================================================${NC}\n"
  printf "${GRN}Installing plugin ${wpi_plugins_single__name[$i]}${NC}\n"
  printf "${GRN}=================================================${NC}\n"
  # Running plugin install via wp-cli
  if [ "${wpi_plugins_single__package[$i]}" == "wp-cli" ]; then
    # Install from zip
    if [[ ${wpi_plugins_single__package_zip[$i]} =~ $zip ]]; then
      wp plugin install ${wpi_plugins_single__package_zip[$i]} --quiet
    else
      # Get plugin version from config
      if [ "${wpi_plugins_single__package_ver[$i]}" != "*" ]; then
          version="--version=${wpi_plugins_single__package_ver[$i]} --force"
      fi
      # Default plugin install via wp-cli
      wp plugin install ${wpi_plugins_single__name[$i]} --quiet ${version}
    fi
  elif [ "${wpi_plugins_single__package[$i]}" == "bitbucket" ]; then
    # Install plugin from private bitbacket repository via composer
    project=${wpi_plugins_single__name[$i]}
    project_ver=${wpi_plugins_single__package_ver[$i]}
    composer=${wpi_plugins_single__install_composer[$i]}
    repo_name=$(echo ${project} | cut -d"/" -f2)
    no_dev="--no-dev"

    # OAUTH for bitbucket via key and secret
    if [ ! -z "${wpi_plugins_single__package_key[$i]}" ] && [ ! -z "${wpi_plugins_single__package_secret[$i]}" ]; then
      composer config --global --auth bitbucket-oauth.bitbucket.org ${wpi_plugins_single__package_key[$i]} ${wpi_plugins_single__package_secret[$i]}
    fi

    # Get vcs for local and dev
    if [ "$cur_env" != "production" ] && [ "$cur_env" != "staging" ]; then
      # Reset --no-dev
      no_dev=""

      # Get plugin version from config
      if [ "${wpi_plugins_single__package_ver[$i]}" != "*" ]; then
          version=${wpi_plugins_single__package_ver[$i]}
      else
          version="dev-master"
      fi
      composer config repositories.$project '{"type":"vcs","url":"git@bitbucket.org:'$project'.git"}'
      composer require $project:$version --update-no-dev --quiet
    else
      # Remove the package from composer cache
      if [ -d ~/.cache/composer/files/$project ]; then
        rm -rf ~/.cache/composer/files/$project
      fi
      project_zip="https://bitbucket.org/$project/get/$project_ver.zip"
      composer config repositories.$project '{"type":"package","package": {"name": "'$project'","version": "'$project_ver'","type": "wordpress-plugin","dist": {"url": "'$project_zip'","type": "zip"}}}'
      composer require $project:$project_ver --update-no-dev --quiet
    fi

    # Run install scripts like composer/npm etc
    if [ "$composer" == "install" ] || [ "$composer" == "update" ]; then
      composer $composer -d ${PWD}/web/app/plugins/$repo_name $no_dev --quiet
    elif [ "$composer" == "dump-autoload" ]; then
      composer -d ${PWD}/web/app/plugins/$repo_name dump-autoload -o --quiet
    fi

    # Run npm scripts
    if [ "${wpi_plugins_single__install_npm[$i]}" == "install" ] ; then
      # run npm install
      npm i --prefix ${PWD}/web/app/plugins/$repo_name
      if [ "$cur_env" == "production" ] || [ "$cur_env" == "staging" ]; then
        eval ${wpi_plugins_single__install_npm_prod[$i]} --prefix ${PWD}/web/app/plugins/$repo_name
      else
        eval ${wpi_plugins_single__install_npm_dev[$i]} --prefix ${PWD}/web/app/plugins/$repo_name
      fi
    fi
  fi
done
