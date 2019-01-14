#!/bin/bash

# This is an helper to setup this docker compose Drupal stack on Ubuntu 16.04/18.04.
# This script must be run as ubuntu user with sudo privileges without password.
# We assume that docker and docker-compose is properly installed when using this
# script (From cloud config files in this folder).
# This script is used with a cloud config setup from this folder.

# Project variables.
_USER="ubuntu"
_GROUP="ubuntu"
_BASE=${1-"default"}
_INSTALL_DRUPAL=${2-}
_PROJECT_PATH="$HOME/docker-compose-drupal"

# Ensure permissions.
sudo chown -R $_USER:$_GROUP $HOME

# Set Docker group to our user (temporary fix?).
sudo usermod -a -G docker $_USER

# Get a Docker compose stack.
if ! [ -d "${_PROJECT_PATH}" ]; then
  echo -e "\n>>>>\n[setup::info] Get Docker stack...\n<<<<\n"
  git clone https://gitlab.com/mog33/docker-compose-drupal.git ${_PROJECT_PATH}
  if ! [ -f "${_PROJECT_PATH}/docker-compose.tpl.yml" ]; then
    echo -e "\n>>>>\n[setup::error] Failed to download DockerComposeDrupal :(\n<<<<\n"
    exit 1
  fi
else
  echo -e "\n>>>>\n[setup::notice] Docker stack already here!\n<<<<\n"
  exit 1
fi

# Set-up and launch this Docker compose stack.
echo -e "\n>>>>\n[setup::info] Prepare Docker stack...\n<<<<\n"
(cd $_PROJECT_PATH && make setup)

# Get stack variables and functions.
if ! [ -f $_PROJECT_PATH/scripts/helpers/common.sh ]; then
  echo -e "\n>>>>\n[setup::error] Missing $_PROJECT_PATH/scripts/helpers/common.sh file!"
  exit 1
fi
source $_PROJECT_PATH/scripts/helpers/common.sh "no-running-check"

echo -e "\n>>>>\n[setup::info] Prepare stack ${_BASE}\n<<<<\n"
if [ -f "$STACK_ROOT/samples/$_BASE.yml" ]; then
  cp $STACK_ROOT/samples/$_BASE.yml $STACK_ROOT/docker-compose.yml
fi

# Set-up Composer.
if ! [ -f "/usr/bin/composer" ]; then
  echo -e "\n>>>>\n[setup::info] Set-up Composer and dependencies...\n<<<<\n"
  cd $HOME
  curl -sS https://getcomposer.org/installer | php -- --install-dir=$HOME --filename=composer
  sudo mv $HOME/composer /usr/bin/composer
  sudo chmod +x /usr/bin/composer
  /usr/bin/composer global require "hirak/prestissimo:^0.3" "drupal/coder"
else
  echo -e "\n>>>>\n[setup::notice] Composer already here!\n<<<<\n"
  # Install dependencies just in case.
  /usr/bin/composer global require "hirak/prestissimo:^0.3" "drupal/coder"
fi

# Set-up Code sniffer.
echo -e "\n>>>>\n[setup::info] Set-up Code sniffer and final steps...\n<<<<\n"
if [ -f "$HOME/.config/composer/vendor/bin/phpcs" ]; then
  $HOME/.config/composer/vendor/bin/phpcs --config-set installed_paths $HOME/.config/composer/vendor/drupal/coder/coder_sniffer
fi

if ! [ -z ${_INSTALL_DRUPAL} ]; then
  echo -e "\n>>>>\n[setup::info] Download Drupal ${_INSTALL_DRUPAL}\n<<<<\n"
  $STACK_ROOT/scripts/install-drupal.sh download ${_INSTALL_DRUPAL}
fi

docker-compose --file "${STACK_ROOT}/docker-compose.yml" up -d --build

if ! [ -z ${_INSTALL_DRUPAL} ]; then
  echo -e "\n>>>>\n[setup::info] Install Drupal ${_INSTALL_DRUPAL}\n<<<<\n"
  $STACK_ROOT/scripts/install-drupal.sh setup ${_INSTALL_DRUPAL}
fi

# Add composer path to environment.
cat <<EOT >> $HOME/.profile
PATH=\$PATH:$HOME/.config/composer/vendor/bin
EOT

# Add docker, phpcs, drush and drupal console aliases.
cat <<EOT >> $HOME/.bash_aliases
# Docker
alias dk='docker'
# Docker-compose
alias dkc='docker-compose'
# Drush and Drupal console
alias drush="$STACK_ROOT/scripts/drush"
alias drupal="$STACK_ROOT/scripts/drupal"
# Check Drupal coding standards
alias csdr="$HOME/.config/composer/vendor/bin/phpcs --standard=Drupal --extensions='php,module,inc,install,test,profile,theme,info'"
# Check Drupal best practices
alias csbpdr="$HOME/.config/composer/vendor/bin/phpcs --standard=DrupalPractice --extensions='php,module,inc,install,test,profile,theme,info'"
# Fix Drupal coding standards
alias csfixdr="$HOME/.config/composer/vendor/bin/phpcbf --standard=Drupal --extensions='php,module,inc,install,test,profile,theme,info'"
EOT

# Convenient links.
if ! [ -d "$HOME/drupal" ]; then
  ln -s $STACK_DRUPAL_ROOT $HOME/drupal
fi
if ! [ -d "$HOME/dump" ]; then
  ln -s ${STACK_ROOT}${HOST_DATABASE_DUMP#'./'} $HOME/dump
fi
if ! [ -d "$HOME/scripts" ]; then
  ln -s ${STACK_ROOT}/scripts $HOME/scripts
fi

# Set up tools from stack.
if [ -d "$STACK_ROOT" ]; then
  echo -e "\n>>>>\n[setup::info] Setup Docker stack tools...\n<<<<\n"
  $STACK_ROOT/scripts/get-tools.sh install
fi

# Ensure permissions.
sudo chown -R $_USER:$_GROUP $HOME

echo -e "\n>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n
[setup::info] Docker compose stack install finished!\n
<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n"
