#!/bin/bash
# Roland Ross Hadi - Jan 2017
# This version uses September 2017 august stretch image, please use this image
# 

# Check if user is root
if [ "$EUID" -ne 0 ]
	then echo "Must be root"
	exit
fi

# Check parameters are complete arg1=password arg2=wifi-name
if [[ $# -lt 1 ]]; 
	then echo "You need to pass a password!"
	echo "Usage:"
	echo "sudo $0 yourChosenPassword [apName]"
	exit
fi

# Initialize wifi user name and password
APPASS="$1"
APSSID="rpiUser"

if [[ $# -eq 2 ]]; then
	APSSID=$2
fi

# Update and Upgrade apt
sudo apt-get update -yqq
sudo apt-get upgrade -yqq

# Install nginx
sudo apt-get install nginx -yqq

# Install mysql server
sudo apt-get install mysql-server -yqq

# Make sure that NOBODY can access the server without a password
mysql -e "UPDATE mysql.user SET Password = PASSWORD('$APPASS') WHERE User = 'root'"
mysql -e "UPDATE mysql.user SET plugin = null where user ='root';"
# Kill the anonymous users
mysql -e "DROP USER ''@'localhost'"
# Because our hostname varies we'll use some Bash magic here.
mysql -e "DROP USER ''@'$(hostname)'"
# Kill off the demo database
mysql -e "DROP DATABASE test"
# Make our changes take effect
mysql -e "FLUSH PRIVILEGES"

# Install PHP
sudo apt-get install php-fpm php-mysql php-mbstring php-xml php-tokenizer php-pdo -yqq

# Update php.ini file
upload_max_filesize=2G
post_max_size=2G
max_execution_time=18000
max_input_time=18000
max_input_vars=30000

sed -i -- 's/; max_input_vars/max_input_vars/g' /etc/php/7.0/fpm/php.ini
sed -i -- 's/;max_input_vars/max_input_vars/g' /etc/php/7.0/fpm/php.ini

for key in upload_max_filesize post_max_size max_execution_time max_input_time
do
 sed -i "s/^\($key\).*/\1 = $(eval echo \${$key})/" /etc/php/7.0/fpm/php.ini
done

sed -i -- 's/max_input_vars = 1000/max_input_vars = 30000/g' /etc/php/7.0/fpm/php.ini

# Install hostapd and dnsmasq
sudo apt-get remove --purge hostapd -yqq
sudo apt-get install hostapd dnsmasq -yqq

# Update /etc/dnsmasq.conf
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig  
cat > /etc/dnsmasq.conf <<EOF
interface=wlan0      # Use interface wlan0  
listen-address=172.24.1.1 # Explicitly specify the address to listen on  
bind-interfaces      # Bind to the interface to make sure we aren't sending things elsewhere  
server=8.8.8.8       # Forward DNS requests to Google DNS  
domain-needed        # Don't forward short names  
bogus-priv           # Never forward addresses in the non-routed address spaces.  
dhcp-range=172.24.1.50,172.24.1.150,12h # Assign IP addresses between 172.24.1.50 and 172.24.1.150 with a 12 hour lease time  
EOF

# Update /etc/hostapd/hostapd.conf
cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
hw_mode=g
channel=10
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
wpa_passphrase=$APPASS
ssid=$APSSID
ieee80211n=1
wmm_enabled=1
ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]
EOF

# Update /etc/network/interfaces
cat >> /etc/network/interfaces <<EOF
# Added by rPi Access Point Setup
allow-hotplug wlan0
iface eth0 inet dhcp
iface wlan0 inet static
	address 172.24.1.1
	netmask 255.255.255.0
	network 172.24.1.0
	broadcast 172.24.1.255
EOF

# Update /etc/default/hostapd
sed -i -- 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/g' /etc/default/hostapd

# Update /etc/php/7.0/fpm/php.ini
sed -i -- 's/#cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g' /etc/php/7.0/fpm/php.ini

# Update /etc/nginx/sites-available/default
sed -i -- 's/listen [::]/#listen [::]/g' /etc/nginx/sites-available/default
sed -i -- 's/=404;/\/index.php$is_args$args;/g' /etc/nginx/sites-available/default
sed -i -- 's/index index.html index.htm index.nginx-debian.html/index index.php index.html index.htm index.nginx-debian.html/g' /etc/nginx/sites-available/default
sed -i -- 's/#location ~/location ~/g' /etc/nginx/sites-available/default
sed -i -- 's/\t#}/\t}/g' /etc/nginx/sites-available/default
sed -i -- 's/#\tdeny/\tdeny/g' /etc/nginx/sites-available/default
sed -i -- 's/#\tinclude snippets/\tinclude snippets/g' /etc/nginx/sites-available/default
sed -i -- 's/#\tfastcgi_pass unix/\tfastcgi_pass unix/g' /etc/nginx/sites-available/default
sed -i -- 's/fpm.sock;/fpm.sock;\n\t\tfastcgi_buffers 16 16k;\n\t\tfastcgi_buffer_size 32k;/g' /etc/nginx/sites-available/default
sed -i -- 's/root \/var\/www\/html/root \/var\/www\/html\/public/g' /etc/nginx/sites-available/default

# Use /etc/sysctl.conf
sed -i -- 's/#net.ipv4.ip_forward/net.ipv4.ip_forward/g' /etc/sysctl.conf
sed -i -- 's/exit/iptables-restore < \/etc\/iptables.ipv4.nat\nexit/g' /etc/sysctl.conf

# Use /etc/dhcpcd.conf
echo "denyinterfaces wlan0" >> /etc/dhcpcd.conf

# Use /proc/sys/net/ipv4/ip_forward
sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE  
sudo iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT  
sudo iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT 
sudo sh -c "iptables-save > /etc/iptables.ipv4.nat"
iptables-restore < /etc/iptables.ipv4.nat

# Add hostapd and dnsmasq on startup
systemctl enable hostapd
systemctl enable dnsmasq

# Start hostapd and dnsmasq
sudo service hostapd start
sudo service dnsmasq start

# import data from .sql file
echo "mysql -u root -p mysql_db_name<mysql_db_data.sql"
echo "All done! Please reboot"

#wget https://raw.githubusercontent.com/rolandhadi/raspberry-pi-lamp-server/main/rpi-lamp-server-setup.sh -O /var/rpi-lamp-server-setup.sh
#chmod +x /var/rpi-lamp-server-setup.sh
#cd /var
#./rpi-lamp-server-setup.sh Qwer123$ rpiServer