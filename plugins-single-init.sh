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

cur_env=$(cur_env)
zip="^(https|git)(:\/\/|@)([^\/:]+)[\/:]([^\/:]+)\/([^\/:]+)\/([^\/:]+)\/(.+).zip$"
# Create array of plugin list and loop
mapfile -t plugins < <( wpi_yq 'plugins.single.[*].name' )
# Get all single plugins and run install by type
for i in "${!plugins[@]}"
do
  version=""
  project=$(wpi_yq plugins.single.[$i].name)
  project_ver=$(wpi_yq plugins.single.[$i].ver)
  repo_name=$(echo ${project} | cut -d"/" -f2)
  no_dev="--no-dev"
  dev_commit=$(echo ${project_ver} | cut -d"#" -f1)
  ver_commit=$(echo ${project_ver} | cut -d"#" -f2)
  setup_name=$(wpi_yq plugins.single.[$i].setup)

  # Switch package to symlink for specific environment
  if [[ "$(wpi_yq plugins.single.[$i].symlink.env)" == "$cur_env" ]]; then
    symlink_env=$(wpi_yq plugins.single.[$i].symlink.env)
    symlink_path=$(wpi_yq plugins.single.[$i].symlink.path)
    app_path=$(wpi_yq env.$symlink_env.app_dir)
    app_content=$(wpi_yq env.$symlink_env.app_content)
    if [[ -d "$symlink_path" ]]; then
      printf "${GRN}====================================================${NC}\n"
      printf "${GRN}Creating symlink for $repo_name                     ${NC}\n"
      printf "${GRN}====================================================${NC}\n"
      ln -s $symlink_path ${app_path%/}${app_content%/}/plugins/$repo_name
      continue
    fi
  fi

  printf "${GRN}====================================================${NC}\n"
  printf "${GRN}Installing plugin $(wpi_yq plugins.single.[$i].name)${NC}\n"
  printf "${GRN}====================================================${NC}\n"

  # Get plugin version from config
  if [ "$project_ver" != "null" ] && [ "$project_ver" ] && [ "$project_ver" != "*" ]; then
    json_ver=$project_ver
    # check for commit version
    if [ "$dev_commit" == "dev-master" ]; then
      json_ver="dev-master"
    fi
  else
    # default versions
    json_ver="dev-master"
    project_ver="dev-master"
    ver_commit="master"
  fi

  # Get plugin branch keys
  mapfile -t branch < <( wpi_yq "plugins.single.[$i].branch" 'keys' )
  # Get plugin branch by current env
  for b in "${!branch[@]}"
  do
    if [ "${branch[$b]}" == $cur_env ]; then
      # Current branch name
      branch_name=$(wpi_yq "plugins.single.[$i].branch.$cur_env")
      # Current setup name
      name=$(wpi_yq plugins.single.[$i].setup)
      # Create oauth token by key:secret
      bitbucket_token=$(curl -s -X POST -u "$(wpi_yq init.setup.$name.bitbucket.key):$(wpi_yq init.setup.$name.bitbucket.secret)" "https://bitbucket.org/site/oauth2/access_token" -d grant_type=client_credentials | jq -r ".access_token")
      # Get the last commit of current branch
      branch_commit_id=$(curl -s --request GET \
      --url "https://api.bitbucket.org/2.0/repositories/$project/commits/$branch_name" \
      --header "Authorization: Bearer $bitbucket_token" \
      --header "Accept: application/json" | jq -r ".values[0].hash")
      ver_commit=$branch_commit_id
    fi
  done

  # Running plugin install via wp-cli
  if [ "$(wpi_yq plugins.single.[$i].package)" == "wp-cli" ]; then
    # Install from zip
    if [[ $(wpi_yq plugins.single.[$i].zip) =~ $zip ]]; then
      wp plugin install $(wpi_yq plugins.single.[$i].zip) --force --quiet
    else
      # Get plugin version from config
      if [ "$(wpi_yq plugins.single.[$i].ver)" != "null" ] && [ "$(wpi_yq plugins.single.[$i].ver)" ] && [ "$(wpi_yq plugins.single.[$i].ver)" != "*" ]; then
        version="--version=$project_ver --force"
      fi
      # Default plugin install via wp-cli
      wp plugin install $(wpi_yq plugins.single.[$i].name) --force --quiet ${version}
    fi
  elif [ "$(wpi_yq plugins.single.[$i].package)" == "bitbucket" ] && [ "$(wpi_yq init.workflow)" == "bedrock" ]; then
    # Install plugin from private/public bitbucket repository via composer
    # Check for setup settings
    if [ "$(wpi_yq plugins.single.[$i].setup)" != "null" ] && [ "$(wpi_yq plugins.single.[$i].setup)" ]; then
      name=$(wpi_yq plugins.single.[$i].setup)

      # OAUTH for bitbucket via key and secret
      if [ "$(wpi_yq init.setup.$name.bitbucket.key)" != "null" ] && [ "$(wpi_yq init.setup.$name.bitbucket.key)" ] && [ "$(wpi_yq init.setup.$name.bitbucket.secret)" != "null" ] && [ "$(wpi_yq init.setup.$name.bitbucket.secret)" ]; then
        composer config --global --auth bitbucket-oauth.bitbucket.org $(wpi_yq init.setup.$name.bitbucket.key) $(wpi_yq init.setup.$name.bitbucket.secret)
      fi
    fi

    # Get GIT for local and dev
    if [ "$cur_env" == "local" ] || [ "$cur_env" == "dev" ]; then
      # Reset --no-dev
      no_dev=""

      # Composer config and install - GIT version
      composer config repositories.$project '{"type":"package","package": {"name": "'$project'","version": "'$json_ver'","type": "wordpress-plugin","source": {"url": "https://bitbucket.org/'$project'","type": "git","reference": "master"}}}'
      composer require $project:$project_ver --update-no-dev --quiet
    else
      # Remove the package from composer cache
      if [ -d ~/.cache/composer/files/$project ]; then
        rm -rf ~/.cache/composer/files/$project
      fi

      # Composer config and install - ZIP version
      project_zip="https://bitbucket.org/$project/get/$ver_commit.zip"
      composer config repositories.$project '{"type":"package","package": {"name": "'$project'","version": "'$project_ver'","type": "wordpress-plugin","dist": {"url": "'$project_zip'","type": "zip"}}}'
      composer require $project:$project_ver --update-no-dev --quiet
    fi
  elif [ "$(wpi_yq plugins.single.[$i].package)" == "github" ] && [ "$(wpi_yq init.workflow)" == "bedrock" ]; then
    # Install plugin from private bitbucket repository via composer
    project=$(wpi_yq plugins.single.[$i].name)
    project_ver=$(wpi_yq plugins.single.[$i].ver)
    repo_name=$(echo ${project} | cut -d"/" -f2)
    no_dev="--no-dev"

    # Check for setup settings
    if [ "$(wpi_yq plugins.single.[$i].setup)" != "null" ] && [ "$(wpi_yq plugins.single.[$i].setup)" ]; then
      name=$(wpi_yq plugins.single.[$i].setup)

      # OAUTH for github via key and secret
      if [ "$(wpi_yq init.setup.$name.github-token)" != "null" ] && [ "$(wpi_yq init.setup.$name.github-token)" != "null" ] && [ "$(wpi_yq init.setup.$name.github-token)" ]; then
        composer config -g github-oauth.github.com $(wpi_yq init.setup.$name.github-token)
      fi
    fi

    # Get GIT for local and dev
    if [ "$cur_env" == "local" ] || [ "$cur_env" == "dev" ]; then
      # Reset --no-dev
      no_dev=""

      # Composer config and install - ZIP version
      composer config repositories.$project '{"type":"package","package": {"name": "'$project'","version": "'$json_ver'","type": "wordpress-plugin","source": {"url": "git@github.com:'$project'.git","type": "git","reference": "master"}}}'
      composer require $project:$project_ver --update-no-dev --quiet
    else
      # Remove the package from composer cache
      if [ -d ~/.cache/composer/files/$project ]; then
        rm -rf ~/.cache/composer/files/$project
      fi

      # Composer config and install - ZIP version
      composer config repositories.$project '{"type":"package","package": {"name": "'$project'","version": "'$json_ver'","type": "wordpress-plugin","dist": {"url": "https://github.com/'$project'/archive/'$ver_commit'.zip","type": "zip","reference": "master"}}}'
      composer require $project:$project_ver --update-no-dev --quiet
    fi
  fi

  # Check if setup exist
  if [ "$setup_name" != "null" ] && [ "$setup_name" ]; then
    composer=$(wpi_yq init.setup.$setup_name.composer)
    # Run install composer script in the plugin
    if [ "$composer" != "null" ] && [ "$composer" ] && [ "$composer" == "install" ] || [ "$composer" == "update" ]; then
      composer $composer -d ${PWD}/web/app/plugins/$repo_name $no_dev --quiet
    elif [ "$composer" != "null" ] && [ "$composer" ] && [ "$composer" == "dump-autoload" ]; then
      composer dump-autoload -o -d ${PWD}/web/app/plugins/$repo_name --quiet
    elif [ "$composer" != "null" ] && [ "$composer" ] && [ "$composer" == "install && dump-autoload" ]; then
      composer install -d ${PWD}/web/app/plugins/$repo_name $no_dev --quiet
      composer dump-autoload -o -d ${PWD}/web/app/plugins/$repo_name --quiet
    fi

    # Run npm scripts
    if [ "$(wpi_yq init.setup.$setup_name.npm)" != "null" ] && [ "$(wpi_yq init.setup.$setup_name.npm)" ]; then
      # run npm install
      npm i &> /dev/null --prefix ${PWD}/web/app/plugins/$repo_name
      if [ "$cur_env" == "production" ] && [ "$cur_env" == "staging" ]; then
        eval $(wpi_yq init.setup.$setup_name.npm.prod) --prefix ${PWD}/web/app/plugins/$repo_name
      else
        eval $(wpi_yq init.setup.$setup_name.npm.dev) --prefix ${PWD}/web/app/plugins/$repo_name
      fi
    fi
  fi
done
