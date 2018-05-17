# kubernetes-on-embedded
Build your own kubernetes datacenter with hybrid embedded devices

![Layout:](layout.png)

Wir bauen einen kompleten Kubernetes-Cluster auf Embedded-Hardware. Dazu benutzen wir einen EdgeRouterX, 2 WLAN-Router, 2 Switche, ein Intel UP-Board und für den eigentlichen K8S-Cluster Raspberry Pi's.


## Einkaufswagen füllen, bestellen, bezahlen, installieren und Spaß haben!

Alle Komponenten die Ihr braucht um einen Docker PI-Cluster aufzubauen können in der Regel preiswert und zuverlässig bestellt werden. Wir haben uns an der Liste von [Roland Huss](https://ro14nd.de/kubernetes-on-raspberry-pi3) orientiert:

Danke Roland :-)

Wir haben hier den aktuellsten RPI Modell 3B+ genommen, ein RPI 2 funktioniert aber auch, natürlich mit Abstrichen in der Leistung.

Stand 2018-05. ca. 244 Euro

| Anzahl | Teil                                                         | Preis      |
|:-------|:-------------------------------------------------------------|:-----------|
| 3      | [Raspberry Pi 3 B+](https://www.amazon.de/dp/B07BDR5PDW)     | 3 * 41 EUR |
| 3      | [Micro SD Card 32 GB](http://www.amazon.de/dp/B013UDL5RU)    | 3 * 12 EUR |
| 1      | [WLAN Router](http://www.amazon.de/dp/B00XPUIDFQ)            | 24 EUR     |
| 4      | [USB Kabel](http://www.amazon.de/dp/B016BEVNK4)              | 7 EUR      |
| 1      | [USB Stromgerät](http://www.amazon.de/dp/B00PTLSH9G)         | 30 EUR     |
| 1      | [Gehäuse](http://www.amazon.de/dp/B00NB1WPEE)                | 10 EUR     |
| 2      | [Zwischenplatten](http://www.amazon.de/dp/B00NB1WQZW)        | 2 * 7 EUR  |

* Option: Kühler für die PI kaufen und installieren


## SD-Karten für den beehive PI-Cluster vorbereiten

Es gibt mehrere Möglichkeiten ein RPi-Image auf eine SD-Karte zu bekommen. Wir nutzen für diesen Anwendungsfall das [Flash Tool der Hypriot Priraten](https://github.com/hypriot/flash). Als Basis der Installation verwenden wir das aktuelle [Hypriot OS](https://github.com/hypriot/image-builder-rpi/).

### Installation des Werkzeuges Flash unter Linux / OS X

Mit folgendem Befehlen installiert Ihr das Hypriot Flash Tool:

```
curl -O https://raw.githubusercontent.com/hypriot/flash/master/flash
chmod +x flash
sudo mv flash /usr/local/bin/flash
```

### Download des Hypriot OS-Images

Download des Images:

```bash
mkdir OS-Images
cd OS-Images
HOS_VERSION=1.9.0
HOS_URL=https://github.com/hypriot/image-builder-rpi/releases/download
curl -LO ${HOS_URL}/v${HOS_VERSION}/hypriotos-rpi-v${HOS_VERSION}.img.zip
```

Entpacken des Images:

```bash
$ unzip hypriotos-rpi-v${HOS_VERSION}.img.zip
```

### Optional: Erstellen der Konfiguration `user-data.yml`

In dieser Datei können diverse Einstellungen vorgenommen werden, z.B. der zu vergebende Hostname, anzulegende User, oder, wie im folgenden Beispiel, SSH-Public-Keys für den passwortlosen Zugriff:

```yml
users:
  - name: pirate
    gecos: "Hypriot Pirate"
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: users,docker,video,input
    plain_text_passwd: hypriot
    lock_passwd: false
    ssh_pwauth: true
    chpasswd: { expire: false }
    ssh_authorized_keys:
      - 'ssh-ed25519 ABCDEFGHIJKLMNOP0123456789 claus.frein@bee42.com'
```

### Flashen des OS-Images

Nach Erstellung der Datei `user-data.yml` könnt Ihr diese direkt mit auf die SD-Karte flashen. Ansonsten könnt ihr auch nach dem flashen die `user-data.yml` direkt auf dem PI bearbeiten.

```bash
$ flash -n "MY_HOSTNAME" -u "user-data.yml" hypriotos-rpi-v${HOS_VERSION}.img
```

## Raspberry-Pi starten

Nach dem Einsetzen der Karten könnt Ihr den Raspberry-PI starten. Wenn alles geklappt sollte dieser mit dem WLAN verbunden sein. Nun könnt Ihr Euch mit dem PI per SSH verbinden.

```bash
$ ssh pirate@<ip>
```
__Frage__: Wie bekommt eigentlich heraus welche IP dem PI vom DHCP Server zugeordnet wurde?

```
# install nmap
$ brew install nmap
$ nmap -sn 192.168.178.0/24
```

Das Passwort für den Nutzer __pirate__ lautet: **hypriot**. 

Im Blog der Hypriot Piraten findet Ihr jede Mengen Erklärungen zum Thema Docker on ARM:

* https://blog.hypriot.com/getting-started-with-docker-on-your-arm-device/
* https://hub.docker.com/u/hypriot/


## Kubernetes-Cluster installieren

Für die folgenden Schritte bitte per ssh auf dem ausgewählten Master-RPI springen, z.B.

```bash
ssh pirate@192.168.1.11
```
Für die Installation benötigen wir Root-Rechte, alternativ kann den foilgenden Befehlen jeweils ```sudo``` vorangestellt werden.

```bash
sudo -i 
```

### Installation des Kubernetes-Masters

Zur Ausführung unseres Installationsscripts auf den einzelen RPIs benutzen wir ![Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html). 

Dafür benötigen wir zunächst ein Inventory:

```ini
[k8s-master]
192.168.1.11

[k8s-nodes]
192.168.1.12
192.168.1.13

[k8s-all:children]
k8s-master
k8s-nodes
```

Ansible verbindet sich per SSH auf die zu verwaltenden Rechner, dort muss also öffentlicher SSH-Key hinterlegt sein. Falls Ihr noch keinen habt, hier ein kleines Beispiel:

```bash
#Schlüssel erzeugen
ssh-keygen -t rsa -C "name@example.org"

#Öffentlichen Schlüssel auf alle RPIs kopieren
ssh-copy-id pirate@192.168.1.11
ssh-copy-id pirate@192.168.1.12
...

#ä und testen:

ansible -u pirate --key=PATH_TO_MY_PRIVATE_KEY -m ping all
192.168.1.11 | success >> {
    "changed": false, 
    "ping": "pong"
}

192.168.1.12 | success >> {
    "changed": false, 
    "ping": "pong"
}
```

### Cluster erzeugen

```bash
ansible-playbook -u pirate --key=PATH_TO_MY_PRIVATE_KEY kubernetes.yml
```

Viel Spaß

```
Claus Frein <claus.frein@bee42.com> @cfrein
```