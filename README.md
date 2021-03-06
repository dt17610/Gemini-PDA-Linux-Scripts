Matt's Gemini Documentation
===========================

## Using the automated provisioning:

### Provision a device: provision.sh

Provision a device, from blank/bricked:

This will:
 * Download the FlashTool
 * Download the Debian images
 * Download the Base images required 
 * Flash Debian
 * Reboot the device
 * Wait for networking between the Gemini and your laptop to come up.
 * Run `startup.sh` on your gemini
 
```bash
./provision.sh
```

### First time startup: startup.sh

This will:
 * Connect to the Gemini and insert our ssh-keys.
 * Configure Wifi with wpa_supplicant
 * Prevent closing the lid from suspending the device so that we can run things while in a pocket
 * Set the Timezone
 * Set the Locale
 * Install some sensible base packages
 * Install PHP7.3 for scriptyness.
 * Install some gemini-leds related gubs
 * Purge libreoffice
 * Purge Connman
 * System update
 * Create a new non-gemian user
 * Make them sudoer
 * Copy over our ssh-keys into that new user
 * Set the Gemini Hostname
 * Enable avahi
 
```bash
./run-remote-script.sh startup.sh
```
 
### Compile a kernel: kernel.sh

 * Pull the awful old 3.18 kernel from github, if not already present
 * Duplicate it, ommitting the .git directory into a tmpfs
 
```bash
./run-remote-script.sh kernel.sh
```

## Generally useful packages

I don't know how people quite live without these:

```bash
apt-get update -qq
apt-get -y install \
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

sudo systemctl daemon-reload
sudo systemctl unmask avahi-daemon
sudo systemctl enable avahi-daemon
```

And then do a complete upgrade of all the things.

```bash
apt-get -y upgrade
```

## Configuring WPA Supplicant for automatic wifi connections

It would be quite nice if the device would automatically connect to wifi...
```bash
# Install WPA supplicant 
apt install -y wpasupplicant

# Disable WPA supplicant Service
systemctl stop wpa_supplicant.service
systemctl disable wpa_supplicant.service

# Configure WPA supplicant
curl -K https://raw.githubusercontent.com/matthewbaggett/Gemini-PDA-Linux-Scripts/master/wpa_supplicant.conf -o /etc/wpa_supplicant/wpa_supplicant.conf
```

Don't forget to modify `/etc/wpa_supplicant/wpa_supplicant.conf` to configure your various wifi access points!

## Controlling the lid LEDs
```bash
apt install -y gemian-leds gemian-leds-scripts
/usr/share/gemian-leds/scripts/torch-on && sleep 1 && /usr/share/gemian-leds/scripts/torch-off
```

there are 7 LEDs that appear to be addressed through aw9120:

![Lid LEDs](resources/leds.jpg)

Not pictured: #7, inside on keyboard.

### Manually controlling Lid + Capslock LEDs:

```bash
# echo LED_NUMBER RED GREEN BLUE > /proc/aw9120_operation
echo 1 0 0 0 > /proc/aw9120_operation # LED 1 OFF.
echo 2 3 0 0 > /proc/aw9120_operation # LED 2 RED.
echo 3 3 0 0 > /proc/aw9120_operation # LED 3 GREEN.
echo 4 3 0 0 > /proc/aw9120_operation # LED 4 BLUE.
echo 5 3 3 3 > /proc/aw9120_operation # LED 5 WHITE.
echo 6 3 0 3 > /proc/aw9120_operation # LED 6 PURPLE.
echo 7 0 1 > /proc/aw9120_operation # LED 7 DIM BLUE.
```

LED 7 on the keyboard only has red and blue LEDs attached to it, so the GREEN value is omitted.

### Manually controlling Power LEDs:

```bash
# Turn on green power LED
echo 1 | sudo tee --append /sys/class/leds/green/brightness
# Turn on red power LED
echo 1 | sudo tee --append /sys/class/leds/red/brightness
```

And to turn 'em off again, echo a 0.

This LED cannot be completely turned off when device is charging.

## Running with the lid closed 

If we want things to run in the background, we need it to run with the lid closed:

```bash
sed -i 's|#HandleLidSwitch=.*|HandleLidSwitch=ignore|g' /etc/systemd/logind.conf 
systemctl restart systemd-logind
```

## Installing Docker

```bash
apt-get update -qq
apt install -y apt-transport-https ca-certificates curl
curl -fsSL "https://download.docker.com/linux/debian/gpg" | apt-key add -qq - >/dev/null
echo "deb [arch=arm64] https://download.docker.com/linux/debian stretch stable" > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt install -y docker-ce docker-compose aufs-dev
```

## Decyphering Battery State

Cryptically, battery state seems to be a pain in the ass to obtain on the MTK6769 - A proc device called `/proc/battery_status` is provided which returns an unlabeled CSV of data.

Digging through kernel-3.18, [mtk_cooler_bcct.c](https://github.com/gemian/gemini-linux-kernel-3.18/blob/master/drivers/misc/mediatek/thermal/common/coolers/mtk_cooler_bcct.c#L1023):

 * proc_create("battery_status") 
 * stuct _cl_battery_status_fops
 * _cl_battery_status_open
 * _cl_battery_status_read
 
```bash
matthew@pocket:~$ cat /proc/battery_status 
100,100,4404,2,0,0,5024,500
```
This shows us that the fields returned are:

| internal name    | Explanation           | Example Value | Scale      |
| ---------------- |:--------------------- | -------------:| ---------- |
| bat_info_soc     | ???                   | 100           |            |
| bat_info_uisoc   | ???                   | 100           |            |
| bat_info_vbat    | Battery Voltage       | 4404          | Millivolts |
| bat_info_ibat    | Charging Current      | 2             | mA?        |
| bat_info_mintchr | Charger Min Temp      | 0             |            |
| bat_info_maxtchr | Charger Max Temp      | 0             |            |
| bat_info_vbus    | Supply Voltage        | 5024          | Millivolts |
| bat_info_aicr    | Battery Input Current | 500           | mA?        |

SOC could mean State Of Charge? It looks like it might be percentage charged.

/proc/battery_status is updated almost exactly every 10 seconds. 
No need to poll it faster than that.

## Using PHP as a scripting language

Yeah, I'm trashy like this.

```bash
    apt-get -yq install --no-install-recommends \
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
```