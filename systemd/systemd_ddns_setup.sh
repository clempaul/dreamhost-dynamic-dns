#!/bin/bash

NEWUSER="dreamhostdns"

if [ ! -x /usr/local/bin/dynamicdns.bash ]; then
  echo "Error: Can't find executable at /usr/local/bin/dynamicdns.bash"
  echo "Exiting"
  exit 1
fi

read -r -p "About to create user $NEWUSER, press Ctrl-C to abort"


sudo useradd --system --no-create-home --shell /usr/sbin/nologin $NEWUSER
USERADD_STATUS=$?

if [[ $USERADD_STATUS == 9 ]]; then
  echo "User $NEWUSER already exists"
elif [[ $USERADD_STATUS == 0 ]]; then
  echo "User added"
else
  echo "Error: fail user cannot be added"
  exit 1
fi

#UserHomedir
USER_HOME=$(eval echo ~$NEWUSER)
sudo mkdir -p "$USER_HOME/.config/dreamhost-dynamicdns/"
sudo chown -R $NEWUSER "$USER_HOME/.config/dreamhost-dynamicdns/"

read -r -p "About to cp dreamhost-dynamic-dns.* files to /etc/systemd/system/, press Ctrl-C to abort"
sudo cp dreamhost-dynamic-dns.service /etc/systemd/system/
sudo cp dreamhost-dynamic-dns.timer /etc/systemd/system/
sudo systemctl daemon-reload

read -r -p "About to run 'sudo systemctl enable dreamhost-dynamic-dns.timer', press Ctrl-C to abort"
sudo systemctl enable dreamhost-dynamic-dns.timer

echo "Installed systemd service. Run 'systemctl list-timers --all' to check"

echo "Testing that API KEY exists and is accessible by $NEWUSER"
sudo -u $NEWUSER /usr/local/bin/dynamicdns.bash -l -v
