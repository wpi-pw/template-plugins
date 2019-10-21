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
# Create array of plugin list and loop
mapfile -t plugins < <( wpi_yq 'plugins.single.[*].name' )
# Get all single plugins and run install by type
for i in "${!plugins[@]}"
do
  printf "${GRN}====================================================${NC}\n"
  printf "${GRN}Installing plugin $(wpi_yq plugins.single.[$i].name)${NC}\n"
  printf "${GRN}====================================================${NC}\n"
  # Running plugin install via wp-cli
  if [ "$(wpi_yq plugins.single.[$i].package)" == "wp-cli" ]; then
    # Install from zip
    if [[ $(wpi_yq plugins.single.[$i].zip) =~ $zip ]]; then
      wp plugin install $(wpi_yq plugins.single.[$i].zip) --quiet
    else
      # Get plugin version from config
      if [ "$(wpi_yq plugins.single.[$i].ver)" != "null" ] && [ "$(wpi_yq plugins.single.[$i].ver)" != "*" ]; then
        version="--version=$(wpi_yq plugins.single.[$i].ver) --force"
      fi
      # Default plugin install via wp-cli
      wp plugin install $(wpi_yq plugins.single.[$i].name) --quiet ${version}
    fi
  elif [ "$(wpi_yq plugins.single.[$i].package)" == "bitbucket" ]; then
    # Install plugin from private bitbucket repository via composer
    project=$(wpi_yq plugins.single.[$i].name)
    project_ver=$(wpi_yq plugins.single.[$i].ver)
    repo_name=$(echo ${project} | cut -d"/" -f2)
    no_dev="--no-dev"
    
    # Check for setup settings
    if [ "$(wpi_yq plugins.single.[$i].setup)" != "null" ]; then
      name=$(wpi_yq plugins.single.[$i].setup)

      # OAUTH for bitbucket via key and secret
      if [ "$(wpi_yq plugins.setup.$name.bitbucket.key)" != "null" ] && [ "$(wpi_yq plugins.setup.$name.bitbucket.secret)" != "null" ]; then
        composer config --global --auth bitbucket-oauth.bitbucket.org $(wpi_yq plugins.setup.$name.bitbucket.key) $(wpi_yq plugins.setup.$name.bitbucket.secret)
      fi
    fi

    # Get GIT for local and dev
    if [ "$cur_env" != "production" ] && [ "$cur_env" != "staging" ]; then
      # Reset --no-dev
      no_dev=""

      # Get plugin version from config
      if [ "$(wpi_yq plugins.single.[$i].ver)" != "null" ] && [ "$(wpi_yq plugins.single.[$i].ver)" != "*" ]; then
          version=$(wpi_yq plugins.single.[$i].ver)
      else
          version="dev-master"
      fi
      # Composer config and install - GIT version
      composer config repositories.$project '{"type":"package","package": {"name": "'$project'","version": "'$version'","type": "wordpress-plugin","source": {"url": "https://bitbucket.org/'$project'","type": "git","reference": "master"}}}'
      composer require $project:$version --update-no-dev --quiet
    else
      # Remove the package from composer cache
      if [ -d ~/.cache/composer/files/$project ]; then
        rm -rf ~/.cache/composer/files/$project
      fi
      
      # Get plugin version from config
      if [ "$(wpi_yq plugins.single.[$i].ver)" != "null" ] && [ "$(wpi_yq plugins.single.[$i].ver)" != "*" ]; then
          project_ver=$(wpi_yq plugins.single.[$i].ver)
      else
          project_ver="master"
      fi
      # Composer config and install - ZIP version      
      project_zip="https://bitbucket.org/$project/get/$project_ver.zip"
      composer config repositories.$project '{"type":"package","package": {"name": "'$project'","version": "'$project_ver'","type": "wordpress-plugin","dist": {"url": "'$project_zip'","type": "zip"}}}'
      composer require $project:$project_ver --update-no-dev --quiet
    fi

    # Check if setup exist
    if [ "$(wpi_yq plugins.single.[$i].setup)" != "null" ]; then
      name=$(wpi_yq plugins.single.[$i].setup)
      composer=$(wpi_yq plugins.setup.$name.composer)
      # Run install composer script in the plugin
      if [ "$composer" != "null" ] && [ "$composer" == "install" ] || [ "$composer" == "update" ]; then
        composer $composer -d ${PWD}/web/app/plugins/$repo_name $no_dev --quiet
      elif [ "$composer" != "null" ] && [ "$composer" == "dump-autoload" ]; then
        composer -d ${PWD}/web/app/plugins/$repo_name dump-autoload -o --quiet
      fi
    fi

    # Run npm scripts
    if [ "$(wpi_yq plugins.setup.$name.npm" != "null" ]; then
      # run npm install
      npm i --prefix ${PWD}/web/app/plugins/$repo_name
      if [ "$cur_env" == "production" ] || [ "$cur_env" == "staging" ]; then
        eval $(wpi_yq plugins.setup.$name.npm.prod) --prefix ${PWD}/web/app/plugins/$repo_name
      else
        eval $(wpi_yq plugins.setup.$name.npm.dev) --prefix ${PWD}/web/app/plugins/$repo_name
      fi
    fi
  fi
done
