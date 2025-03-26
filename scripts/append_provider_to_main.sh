#! /bin/bash

# set the home path
HOME_PATH=$(
  cd "$(dirname "$0")"
  cd ..
  pwd
)
echo $HOME_PATH

# given a main.tf file, this script will append the provider block to the end of the file
main_file=$(pwd)/$1

# get the content
main=$(cat $main_file)
provider=$(cat $HOME_PATH/scripts/provider.tf)

# if the content of main contains the provider block, then do nothing
if [[ $main == *"$provider"* ]]; then
  echo "The provider block already exists in the main.tf file."
  exit 0
fi

cat <<EOF >/tmp/main.tf
$main

$provider
EOF
mv /tmp/main.tf $main_file
