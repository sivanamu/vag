#!/bin/sh

RELF=/etc/os-release
if [ -f $RELF ]; then
  source $RELF
else
  echo "unknown os"
  exit 1
fi

case $ID in
  "centos") echo ::: centos; DNF=yum; DNFMNG=yum-config-manager;;
  "fedora") echo ::: fedora; DNF=dnf; DNFMNG="dnf config-manager";;
esac

if [ -d /home/vagrant ]; then
  VUSER=vagrant
else
  VUSER=$ID
fi

# --- epel and uis for centos ---
if [ $ID == centos ]; then
  rpm -ivh https://dl.fedoraproject.org/pub/epel/7/x86_64/Packages/e/epel-release-7-11.noarch.rpm
  rpm -ivh https://centos7.iuscommunity.org/ius-release.rpm
fi

# --- misc -------------------------
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
setenforce Permissive

if [ -d /vagrant/home ]; then
  su ${VUSER} -c "cp -R /vagrant/home/. /home/${VUSER}/"
   mkdir -p /root/.ssh/
   cp /home/${VUSER}/.ssh/* /root/.ssh/
fi

echo DOCKER_PKG_REPO: $DOCKER_PKG_REPO
if [ $DOCKER_PKG_REPO == docker.com ]; then
  # --- use docker.com official repo --------
  curl -o docker-ce.repo https://download.docker.com/linux/${ID}/docker-ce.repo
  $DNFMNG --add-repo docker-ce.repo
  DOCKERPKG=docker-ce
else
  # --- use centos/fedora repo for docker ---
  DOCKERPKG=docker
fi

PKGS="$DOCKERPKG avahi bind-utils emacs-nox unzip rlwrap screen jq \
      openssl-devel curl-devel expat-devel ncurses-devel"
if [ $ID == centos ]; then
  PKGS="$PKGS git2u"
fi
$DNF install -y $PKGS

systemctl start docker
systemctl enable docker
systemctl start avahi-daemon
systemctl enable avahi-daemon

if [ $DOCKERPKG == docker ]; then
  DR=dockerroot # old docker such as 1.12
else
  DR=docker     # new docker such as 17.03
fi
groupadd -f $DR
chown root:$DR /var/run/docker.sock
usermod -a -G $DR $ID > /dev/null 2>&1
usermod -a -G $DR vagrant > /dev/null 2>&1

# --- docker compose ---
curl -L https://github.com/docker/compose/releases/download/1.15.0/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# --- centos only for now ---
if [ $ID == centos ]; then
  # --- kubernetese ---
  $DNFMNG --add-repo /vagrant/kubernetes.repo
  $DNF install -y kubelet kubeadm kubectl kubernetes-cni
  systemctl enable kubelet && systemctl start kubelet

  # --- consul and nomad ---
  CHECKPOINT_URL="https://checkpoint-api.hashicorp.com/v1/check"
  for COMP in consul nomad; do
    T_VER=$(curl -s "${CHECKPOINT_URL}/${COMP}" | jq .current_version | tr -d '"')
    curl -sSL https://releases.hashicorp.com/${COMP}/${T_VER}/${COMP}_${T_VER}_linux_amd64.zip -o ${COMP}.zip
    unzip ${COMP}.zip
    sudo chmod +x ${COMP}
    sudo mv ${COMP} /usr/bin/
    sudo mkdir -p /etc/${COMP}.d
    sudo chmod a+w /etc/${COMP}.d
  done
fi


# --- network ---
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv4.conf.all.forwarding=1
sysctl -w net.ipv4.conf.all.route_localnet=1
sudo iptables -P FORWARD ACCEPT
