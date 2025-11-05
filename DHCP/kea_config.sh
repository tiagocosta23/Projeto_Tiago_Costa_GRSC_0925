#!/bin/bash

### Instalar o serviço Kea DHCP ###
sudo dnf install -y kea

########## Definir IP Estático ##########

# Extrair o nome da interface de rede
netinterface=$(nmcli device status | awk '/connected/ {print $1}' | sed -n '2p')

# Inserir o IP e CIDR desejado
while true: do
    echo "Digite o IP estático desejado: "
    read ip_estatico
    echo "Digite a máscara de rede em CIDR: "
    read cidr
    fullip="${ip_estatico}/${cidr}"
    echo "O IP estático configurado será: $fullip na interface $netinterface"

    IFS="."
    set -- $ip_estatico
    if [$1 -ge 255] || [$2 -gt 255] || [$3 -gt 255] || [$4 -gt 255]; then
        echo "IP inválido. Tente novamente."
        continue
    elif [ $1 -eq 192 ] && [ $2 -eq 168 ]; then
        break
    elif [ $1 -eq 172 ] && [ $2 -ge 16 ] && [ $2 -le 31 ]; then
        break
    elif [ $1 -eq 10 ]; then
        break
    else
        echo "IP público. Insira um IP privado."
    fi
done

# Inserir Gateway
echo "Digite o gateway: "
read gateway

# Inserir DNS
echo "Digite o DNS: "
read dns

# Aplicar as configurações de rede
sudo nmcli connection modify $netinterface ipv4.addresses $fullip ipv4.gateway $gateway ipv4.dns $dns ipv4.method manual
sudo nmcli connection down $netinterface
sudo nmcli connection up $netinterface

########## DHCP KEA ##########

echo "Configurarção do Kea DHCP"

while true: do
    echo "Digite o IP da subnet desejadq: "
    read subnet_dhcp
    echo "Digite a máscara de rede em CIDR: "
    read cidr_dhcp
    full_subnet_dhcp="${subnet_dhcp}/${cidr_dhcp}"
    echo "A subnet configurada será: $full_subnet_dhcp na interface $netinterface"

    IFS="."
    set -- $subnet_dhcp
    if [$1 -ge 255] || [$2 -gt 255] || [$3 -gt 255] || [$4 -gt 255]; then
        echo "IP inválido. Tente novamente."
        continue
    elif [ $1 -eq 192 ] && [ $2 -eq 168 ]; then
        break
    elif [ $1 -eq 172 ] && [ $2 -ge 16 ] && [ $2 -le 31 ]; then
        break
    elif [ $1 -eq 10 ]; then
        break
    else
        echo "IP público. Insira um IP privado."
    fi
done

echo "Defina a máscara"
read mask_dhcp

echo "Defina o range (EX: 192.168.1.100 - 192.168.1.199)"
read range_dhcp

echo "Degite o broadcast"
read broadcast_dhcp

echo "Escolha o DNS"
read dns_dhcp

echo "Defina o gateway"
read gateway_dhcp

echo "Escolha o seu domínio
read domain_dhcp

# Criar backup do ficheiro de configuração original
sudo mv /etc/kea/kea-dhcp4.conf /etc/kea/kea-dhcp4.conf.bak

# Configurar o Kea DHCP
sudo tee /etc/kea/kea-dhcp4.conf > /dev/null <<EOF
{
"Dhcp4": {
    "interfaces-config": {
        // Definir a interface de rede
        "interfaces": [ "$netinterface" ]
    },
    // Configuração do banco de dados de leases
    "lease-database": {
        "type": "memfile",
        "persist": true,
        "name": "/var/lib/kea/dhcp4.leases"
    },
    "renew-timer": 600,
    "rebind-timer": 900,
    "valid-lifetime": 1200,
    "option-data": [
        {
            // Definir servidores DNS
            "name": "domain-name-servers",
            "data": "$dns_dhcp" 
        },
        {
            // Definir o nome de domínio
            "name": "domain-name",
            "data": "$domain_dhcp"
        }
    ],
    "subnet4": [
        {
            // Definir a subnet
            "id": 1,
            "subnet": "$full_subnet_dhcp",
            "pools": [ { "pool": "$range_dhcp" } ],
            "option-data": [
                {
                    // Definir o gateway
                    "name": "routers",
                    "data": "$gateway_dhcp"
                }   
            ]
        }
    ]
}
}
EOF

sudo chown root:kea /etc/kea/kea-dhcp4.conf
sudo chmod 640 /etc/kea/kea-dhcp4.conf
sudo systemctl enable --now kea-dhcp4
sudo firewall-cmd --add-service=dhcp --permanent
sudo firewall-cmd --runtime-to-permanent
