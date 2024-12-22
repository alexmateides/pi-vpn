### I. Prepare the Raspberry Pi

#### 1. Update the system and repos

```shell
sudo apt update && sudo apt upgrade -y
sudo apt install -y raspberrypi-kernel-headers build-essential dkms git
```

#### 2. Reboot after updating

```shell
sudo reboot
```

---

### II. Install chipset driver

#### O. Get chipset version

```shell
lsusb
```

#### 1. Download the driver (using 8821au-20210708)

```shell
sudo apt install -y raspberrypi-kernel-headers build-essential bc dkms git
```

#### 2. Install the driver

```shell
mkdir -p ~/src
cd ~/src
git clone https://github.com/morrownr/8821au-20210708.git
cd ~/src/8821au-20210708
sudo ./install-driver.sh
```

#### 3. Reboot after install

```shell
sudo reboot
```
---

### III. Configure the hotspot and VPN

#### 1. Clone the repo

```shell
cd ~
git clone https://github.com/alexmateides/pi-vpn
cd ~/pi-vpn
sudo ./install.sh
```