#!/bin/bash

#
# Nome: Tiago Costa
# Turma: GRSC 0925
# Projeto: Configuração de um Servidor DHCP com Kea
#

#################################################
#                                               #
#             Definir o IP Estático             #
#                                               #
#################################################

# Inserir o IP e CIDR desejado
while true; do
    echo "Digite o IP estático desejado: "
    read ip_estatico
    echo "Digite a máscara de rede em CIDR: "
    read cidr
    fullip="${ip_estatico}/${cidr}"
    echo "O IP estático configurado será: $fullip na interface ens192"

    IFS="."
    set -- $ip_estatico
    if [ $1 -ge 255 ] || [ $2 -gt 255 ] || [ $3 -gt 255 ] || [ $4 -gt 255 ]; then
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
sudo nmcli connection up ens192
sudo nmcli connection modify ens192 ipv4.addresses "$fullip" ipv4.gateway "$gateway" ipv4.dns "$dns" ipv4.method manual
sudo nmcli connection down ens192
sudo nmcli connection up ens192

###################################################
#                                                 #
#           Configuração do serviço DHCP          #
#                                                 #
###################################################

################### Instalar o Kea DHCP #######################

sudo dnf install -y kea

echo "Configurarção do Kea DHCP"

################### Definir a subnet para o serviço DHCP #######################

while true; do
    echo "Digite o IP da subnet desejada: "
    read subnet_dhcp
    echo "Digite a máscara de rede em CIDR: "
    read cidr_dhcp
    full_subnet_dhcp="${subnet_dhcp}/${cidr_dhcp}"
    echo "A subnet configurada será: $full_subnet_dhcp na interface ens192"

    IFS="."
    set -- $subnet_dhcp
    if [ $1 -ge 255 ] || [ $2 -gt 255 ] || [ $3 -gt 255 ] || [ $4 -gt 255 ]; then
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

################# Definir o range, DNS, gateway e domínio para o serviço DHCP #######################

echo "Defina o range (EX: 192.168.1.100 - 192.168.1.199)"
read range_dhcp

echo "Escolha o DNS"
read dns_dhcp

echo "Defina o gateway"
read gateway_dhcp

echo "Escolha o seu domínio"
read domain_dhcp

################### Criar o backup e configurar o Kea DHCP #######################

sudo mv /etc/kea/kea-dhcp4.conf /etc/kea/kea-dhcp4.conf.bak 2>/dev/null || true

sudo tee /etc/kea/kea-dhcp4.conf > /dev/null <<EOF
{
"Dhcp4": {
    "interfaces-config": {
        // Definir a interface de rede
        "interfaces": [ "ens192" ]
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
    ],
    "loggers": [
        {  
		    "name": "kea-dhcp4",
		    "output-options": [
			    {
				    "output": "/var/log/kea-dhcp4.log"
			    }
		],
		"severity": "INFO",
		"debuglevel": 0
        }
    ]
}
}
EOF

################### Ajustar permissões, firewall e iniciar o serviço #######################

sudo chown root:kea /etc/kea/kea-dhcp4.conf
sudo chmod 640 /etc/kea/kea-dhcp4.conf
sudo systemctl enable --now kea-dhcp4
sudo firewall-cmd --add-service=dhcp --permanent
sudo firewall-cmd --reload

################### Testar o serviço DHCP #######################

while true; do
    echo "Escolha um dos testes para validar o serviço DHCP:"
    echo "1 - Validação de leases"
    echo "2 - Teste de logs"
    echo "3 - Verificação de escuta"
    echo "4 - Sair"
    read escolha_teste 
    if [ $escolha_teste -eq 1 ]; then
        ### Validaçáo de leases ###
        echo "Validaçáo de leases:"
        cat /var/lib/kea/dhcp4.leases
    elif [ $escolha_teste -eq 2 ]; then
        ### Teste de logs ###
        echo "Teste de logs:"
        tail -f /var/log/kea-dhcp4.log
    elif [ $escolha_teste -eq 3 ]; then
        ### Verificação de escuta ###
        echo "Verificação de escuta:"		
        ss -lun | grep 67	
    elif [ $escolha_teste -eq 4 ]; then
        break
    else
        echo "Escolha inválida. Tente novamente."
    fi
done
