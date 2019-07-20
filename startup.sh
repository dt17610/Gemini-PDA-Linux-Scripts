#!/usr/bin/env bash
# You can run this on the device:
# $ curl -sSL https://raw.githubusercontent.com/matthewbaggett/Gemini-PDA-Linux-Scripts/master/setup.sh | sh
#
# Or, if you've not established wifi on the device yet, you can do it over USB bridged network:
# $ ./payload-inject.sh

set -e

if [ -f ./.gem-config ]; then
    echo "Detected .gem-config, gonna load it."
    . ./.gem-config
    echo " > Gonna rename your Gemini as $GEM_HOSTNAME"
    echo " > Gonna create a user called $GEM_USERNAME"
    echo " > Gonna connect to a wifi called $GEM_WIFI_SSID"
    sleep 3;
fi

echo "Okay, lets configure your Gemini to not suck, yeah?"
if [ -z "$GEM_HOSTNAME" ]; then
    read -p "Enter new hostname: " GEM_HOSTNAME
fi
if [ -z "$GEM_USERNAME" ]; then
    read -p "Username: " GEM_USERNAME
fi
if [ -z "$GEM_PASSWORD" ]; then
    read -p "$GEM_USERNAME's password: " GEM_PASSWORD
fi
if [ -z "$GEM_WIFI_SSID" ]; then
    echo "Enter your first wifi SSID for first-time-setup"
    echo " (don't worry, you can edit these in /etc/wpa_supplicant/wpa_supplicant.conf!)"
    read -p "Wifi SSID: " GEM_WIFI_SSID
fi
if [ -z "$GEM_WIFI_KEY" ]; then
    read -p "Wifi Secret: " GEM_WIFI_KEY
fi
if [ -z "$GEM_TIMEZONE" ]; then
    read -p "Timezone (like Europe/London): " GEM_TIMEZONE
fi

# Try the default password to sudo up.
echo "gemini" | sudo -S true > /dev/null 2>&1

# Configure WPA Supplicant
echo "ctrl_interface=/run/wpa_supplicant" | sudo tee /etc/wpa_supplicant/wpa_supplicant.conf
echo "update_config=1" | sudo tee -a /etc/wpa_supplicant/wpa_supplicant.conf
echo "ap_scan=1" | sudo tee -a /etc/wpa_supplicant/wpa_supplicant.conf
wpa_passphrase $GEM_WIFI_SSID $GEM_WIFI_KEY | sudo tee -a /etc/wpa_supplicant/wpa_supplicant.conf

if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
    echo "Written to /etc/wpa_supplicant/wpa_supplicant.conf OK";
else
    echo "Failed to write to /etc/wpa_supplicant/wpa_supplicant.conf";
fi

# Symlink our config into -wlan0.conf
if [ ! -f /etc/wpa_supplicant/wpa_supplicant-wlan0.conf ]; then
    sudo ln -s /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
fi

# Configure wlan0 interface
echo -e "allow-hotplug wlan0\niface wlan0 inet dhcp\n\twpa-conf /etc/wpa_supplicant/wpa_supplicant.conf" | sudo tee /etc/network/interfaces.d/wlan0

# Try the default password to sudo up.
echo "gemini" | sudo -S true > /dev/null 2>&1

# Touch /etc/fstab incase it doesn't exist - this upsets dhclient if it doesn't.
sudo touch /etc/fstab

# Reload all the things
echo "Reloading systemd"
sudo systemctl daemon-reload
echo "Stopping wpa_supplicant service"
sudo systemctl stop wpa_supplicant.service
echo "Disabling wpa_supplicant service"
sudo systemctl disable wpa_supplicant.service
echo "Enabling wpa_supplicant@wlan0"
sudo systemctl enable wpa_supplicant@wlan0
echo "Restarting wpa_supplicant@wlan0"
sudo systemctl start wpa_supplicant@wlan0

# Prevent closing the lid from sleeping the device
echo "Disabling the lid from sleeping the system.."
sudo sed -i 's|#HandleLidSwitch=.*|HandleLidSwitch=ignore|g' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

# Force DHCP update
sudo dhclient wlan0 -v

# Wait for internet to come up
echo -n "Waiting for internet to come up...";
while ! ping -c 1 -n -w 1 8.8.8.8 &> /dev/null
do
    echo -n "."
    sleep 1;
done
echo " [Done!]"

# Try the default password to sudo up.
echo "gemini" | sudo -S true > /dev/null 2>&1

# Set timezone
if [[ $(cat /etc/timezone) != $GEM_TIMEZONE ]]; then
    echo -n "Setting timezone to $GEM_TIMEZONE... ";
    sudo ln -fs /usr/share/zoneinfo/$GEM_TIMEZONE /etc/localtime
    sudo dpkg-reconfigure -f noninteractive tzdata
else
    echo "Timezone alreayd set to $GEM_TIMEZONE"
fi

# Set Locale
if [[ $(cat /etc/default/locale) != *"en_GB.UTF-8"* ]]; then
    echo "Configuring locale...";
    echo 'LANG="en_GB.UTF-8"' | sudo tee /etc/default/locale
    for locale in en_US en_GB nl_NL; do
        sudo sed -i -e "s/# $locale.UTF-8 UTF-8/$locale.UTF-8 UTF-8/" /etc/locale.gen
    done
    echo "gemini" | sudo -S dpkg-reconfigure --frontend=noninteractive locales
    echo "gemini" | sudo -S update-locale LANG=en_GB.UTF-8
else
    echo "Skipping configuring Locale, looks like its all set right."
fi;

# Alright, lets go install shit.
echo "Okay, updating APT repos..."
echo "gemini" | sudo -S apt-get update -qq
if [ ! -f /usr/bin/aptitude ]; then
    echo "Installing some default tooling that should have shipped with this thing..."
    echo "gemini" | sudo -S apt-get -yqq install \
        gemian-leds gemian-leds-scripts \
        aptitude \
        openssh-server \
        avahi-daemon \
        curl \
        wget \
        htop \
        iproute2 \
        systemd-sysv \
        locales \
        iputils-ping

    echo "gemini" | sudo -S systemctl daemon-reload
fi

# Install PHP for some scripting goodness.
if [ ! -f /usr/bin/php ]; then
    echo "Install some PHP for scripting goodness."
    sudo apt -y install lsb-release apt-transport-https ca-certificates
    sudo wget -qq -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php7.3.list
    echo "gemini" | sudo -S apt-get update -qq
    echo "gemini" | sudo -S apt-get -yqq install --no-install-recommends \
        php7.3-bcmath \
        php7.3-bz2 \
        php7.3-cli \
        php7.3-curl \
        php7.3-gd \
        php7.3-imap \
        php7.3-intl \
        php7.3-json \
        php7.3-ldap \
        php7.3-mbstring \
        php7.3-memcache \
        php7.3-memcached \
        php7.3-mongodb \
        php7.3-mysql \
        php7.3-opcache \
        php7.3-pgsql \
        php7.3-pspell \
        php7.3-redis \
        php7.3-soap \
        php7.3-sqlite \
        php7.3-xml \
        php7.3-zip
else
    echo "Skipping installing PHP, already installed."
fi
# Add gemian-leds/scripts to PATH
echo -n "Adding gemian-leds/scripts to PATH."
if [ ! -f /etc/profile.d/gemian-leds-path.sh ]; then
    echo "PATH=$PATH:/usr/share/gemian-leds/scripts" | sudo tee /etc/profile.d/gemian-leds-path.sh
    echo " [DONE]";
else
    echo " [Skipped]";
fi

# Test the lid LEDs
echo "Testing the lid LEDs"
sudo /usr/share/gemian-leds/scripts/torch-on
sleep 1
sudo /usr/share/gemian-leds/scripts/torch-off

# Neuter libreoffice
if [ -d /usr/lib/libreoffice ]; then
    sudo dpkg-divert --remove /usr/lib/libreoffice/share/basic/dialog.xlc
    sudo dpkg-divert --remove /usr/lib/libreoffice/share/basic/script.xlc
    sudo apt-get -yq purge libreoffice*
    sudo rm -Rf /usr/lib/libreoffice
else
    echo "Skipping libreoffice removal - Already removed."
fi

# Obliterate Connman
if [ -f /usr/sbin/connmanctl ]; then
    sudo apt-get -yq purge connman
    sudo dhclient wlan0 -v
else
    echo "Skipping Connman removal - Already removed."
fi

# Update the system
echo "Okay, time for the big one - system wide upgrade"
sudo apt-get -y upgrade

# Add the new user
echo "Adding the user $GEM_USERNAME...";
if [ ! -d  /home/$GEM_USERNAME ]; then
    sudo useradd \
        $GEM_USERNAME \
        -m \
        -s /bin/bash \
        -u 100001 \
        -p $(openssl passwd -1 $GEM_PASSWORD)
fi;

# Alter the hostname
if [ $GEM_HOSTNAME != $(cat /etc/hostname) ]; then
    echo "Setting hostname to $GEM_HOSTNAME";
    echo -e "127.0.0.1\t$GEM_HOSTNAME" | sudo tee -a /etc/hosts
    echo -e $GEM_HOSTNAME | sudo tee /etc/hostname
    sudo invoke-rc.d hostname.sh start
    sudo invoke-rc.d networking force-reload
fi

# Avahi
echo "Enabling avahi"
sudo systemctl unmask avahi-daemon
sudo systemctl enable avahi-daemon

# Set up lid lighting
((crontab -l | grep -q 'led-battery-level') && echo 'Skipping adding led-battery-level crontab; Already exists') \
    || ((crontab -l 2>/dev/null; echo "@reboot /home/gemini/bin/led-battery-level") | crontab -)
nohup /home/gemini/bin/led-battery-level &


