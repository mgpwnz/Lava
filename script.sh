#!/bin/bash
# Default variables
function="install"
#git 2.0.0 
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        -in|--install)
            function="install"
            shift
            ;;
        -un|--uninstall)
            function="uninstall"
            shift
            ;;
        *|--)
		break
		;;
	esac
done
install() {
bash_profile=$HOME/.bash_profile
if [ -f "$bash_profile" ]; then
	    . $HOME/.bash_profile
fi
if [ ! $LAVA_ALIAS ]; then
	read -p "Enter validator name: " LAVA_ALIAS
	echo 'export LAVA_ALIAS='\"${LAVA_ALIAS}\" >> $HOME/.bash_profile
fi
echo 'source $HOME/.bashrc' >> $HOME/.bash_profile
. $HOME/.bash_profile
sleep 1
cd $HOME
sudo apt update
sudo apt install -y curl git jq lz4 build-essential

# Install Go
sudo rm -rf /usr/local/go
curl -L https://go.dev/dl/go1.21.6.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
source .bash_profile

cd && rm -rf lava
git clone https://github.com/lavanet/lava
cd lava
git checkout v2.0.0

# Build binary
export LAVA_BINARY=lavad
make install

# Set node CLI configuration
lavad config chain-id lava-testnet-2
lavad config keyring-backend test
lavad config node tcp://localhost:19957

# Initialize the node
lavad init "$OG_ALIAS" --chain-id lava-testnet-2

# Download genesis and addrbook files
curl -L https://snapshots-testnet.nodejumper.io/lava-testnet/genesis.json > $HOME/.lava/config/genesis.json
curl -L https://snapshots-testnet.nodejumper.io/lava-testnet/addrbook.json > $HOME/.lava/config/addrbook.json

# Set seeds
sed -i -e 's|^seeds *=.*|seeds = "3a445bfdbe2d0c8ee82461633aa3af31bc2b4dc0@prod-pnet-seed-node.lavanet.xyz:26656,e593c7a9ca61f5616119d6beb5bd8ef5dd28d62d@prod-pnet-seed-node2.lavanet.xyz:26656,ade4d8bc8cbe014af6ebdf3cb7b1e9ad36f412c0@testnet-seeds.polkachu.com:19956,eb7832932626c1c636d16e0beb49e0e4498fbd5e@lava-testnet-seed.itrocket.net:20656"|' $HOME/.lava/config/config.toml

# Set minimum gas price
sed -i -e 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0.000001ulava"|' $HOME/.lava/config/app.toml

# Set pruning
sed -i \
  -e 's|^pruning *=.*|pruning = "custom"|' \
  -e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' \
  -e 's|^pruning-interval *=.*|pruning-interval = "17"|' \
  $HOME/.lava/config/app.toml

# Change ports
sed -i -e "s%:1317%:19917%; s%:8080%:19980%; s%:9090%:19990%; s%:9091%:19991%; s%:8545%:19945%; s%:8546%:19946%; s%:6065%:19965%" $HOME/.lava/config/app.toml
sed -i -e "s%:26658%:19958%; s%:26657%:19957%; s%:6060%:19960%; s%:26656%:19956%; s%:26660%:19961%" $HOME/.lava/config/config.toml

# Download latest chain data snapshot
curl "https://snapshots-testnet.nodejumper.io/lava-testnet/lava-testnet_latest.tar.lz4" | lz4 -dc - | tar -xf - -C "$HOME/.lava"
sleep 2
cd $HOME
# Create a service
sudo tee /etc/systemd/system/lava.service > /dev/null << EOF
[Unit]
Description=Lava node service
After=network-online.target
[Service]
User=$USER
ExecStart=$(which lavad) start
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable lava.service

# Start the service and check the logs
sudo systemctl start lava.service
sudo journalctl -u lava.service -f --no-hostname -o cat
}
uninstall() {
read -r -p "You really want to delete the node? [y/N] " response
case "$response" in
    [yY][eE][sS]|[yY]) 
        sudo systemctl stop lava
        sudo systemctl disable lava
        sudo rm -rf $(which lavad) $HOME/.lava
    echo "Done"
    cd $HOME
    ;;
    *)
        echo Сanceled
        return 0
        ;;
esac
}
# Actions
sudo apt install wget -y &>/dev/null
cd
$function
