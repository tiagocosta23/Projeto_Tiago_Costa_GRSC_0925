#!/bin/bash

#
# Nome: Tiago Costa
# Turma: GRSC 0925
# Projeto: Configuração de um Servidor DNS com BIND
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

#################################################
#                                               #
#          Configuração do serviço DNS          #
#                                               #
#################################################

################### Definir a subnet para o serviço DNS #######################

echo "Escolha a subnet para o serviço DNS:"
read subnet_dns
echo "Digite a máscara de rede em CIDR: "
read cidr_dns
full_subnet_dns="${subnet_dns}/${cidr_dns}"
echo "A subnet configurada será: $full_subnet_dns na interface ens192"

################### Extrair o octeto final do IP estático para o PTR #######################

IFS="."
set -- $ip_estatico
octeto=$4

################### Definir o IP do www e extrair o octeto final para o PTR #######################

echo "Digite o IP do www: "
read ip_www
IFS="."
set -- $ip_www
octeto_www=$4

################### Definir o reverse DNS #######################

IFS="."
set -- $subnet_dns
reverse_zone="${3}.${2}.${1}"

OCTETO_1=$(echo "$subnet_dns" | cut -d '.' -f1)
OCTETO_2=$(echo "$subnet_dns" | cut -d '.' -f2)
OCTETO_3=$(echo "$subnet_dns" | cut -d '.' -f3)
OCTETO_4=$(echo "$subnet_dns" | cut -d '.' -f4)

################### Instalar e configurar o BIND DNS #######################

sudo dnf install -y bind bind-utils

sudo tee /etc/named.conf > /dev/null <<EOF
acl internal-network {
        $full_subnet_dns;
};

options {
        listen-on port 53 { any; };
        listen-on-v6 { any; };
        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        secroots-file   "/var/named/data/named.secroots";
        recursing-file  "/var/named/data/named.recursing";
        
        allow-query     { localhost; internal-network; };
        allow-transfer  { localhost; };

        recursion yes;

        forward first;
        forwarders { 8.8.8.8; 1.1.1.1; };
};

logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

zone "." IN {
        type hint;
        file "named.ca";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";

zone "empresa.local" IN {
        type primary;
        file "empresa.local.lan";
        allow-update { none; };
};
zone "$reverse_zone.in-addr.arpa" IN {
        type primary;
        file "$reverse_zone.db";
        allow-update { none; };
};
EOF

################### Criar os ficheiro de zona direta #######################

sudo tee /var/named/empresa.local.lan > /dev/null <<EOF
\$TTL 86400
@   IN  SOA     servidordns.empresa.local. root.empresa.local. (
        1761555569  ; Serial
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400       ; Minimum TTL
)
@               IN  NS      servidordns.empresa.local.
servidordns       IN  A       $ip_estatico
@               IN  MX 10   servidordns.empresa.local.
www             IN  A       $ip_www
EOF

################### Criar os ficheiro de zona reversa #######################
echo "$reverse_zone"
echo "${OCTETO_3}.${OCTETO_2}.${OCTETO_1}"
sudo tee /var/named/${OCTETO_3}.${OCTETO_2}.${OCTETO_1}.db > /dev/null <<EOF
\$TTL 86400
@   IN  SOA     servidordns.empresa.local. root.empresa.local. (
        1761555569  ; Serial
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400       ; Minimum TTL
)
@               IN  NS      servidordns.empresa.local.
$octeto         IN  PTR     servidordns.empresa.local.
$octeto_www            IN  PTR     www.empresa.local.
EOF

################## Fazer o CentOS usar o seu próprio DNS ########################

sudo tee /etc/resolv.conf > /dev/null <<EOF
# Generated by NetworkManager
search localdomain empresa.local
nameserver $ip_estatico
EOF
sudo chattr +i /etc/resolv.conf

################### Ajustar permissões, firewall e iniciar o serviço #######################

sudo chown named:named /var/named/empresa.local.lan
sudo chown named:named /var/named/${OCTETO_3}.${OCTETO_2}.${OCTETO_1}.db
sudo firewall-cmd --add-service=dns --permanent
sudo firewall-cmd --reload
sudo systemctl enable --now named
sudo systemctl start named
sudo systemctl status named

################### IP Forwarding e Routing ####################

sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null <<EOF
1
EOF

sudo sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p

sudo iptables -t nat -A POSTROUTING -s 192.168.1.0/24 -o ens160 -j MASQUERADE

sudo firewall-cmd --zone=public --add-masquerade --permanent
sudo firewall-cmd --reload

################### Testar o serviço DNS #######################



while true; do
    echo "Escolha um dos testes para validar o serviço DNS:"
    echo "1 - Teste dig"
    echo "2 - Teste dig reverso"
    echo "3 - Teste nslookup"
    echo "4 - Teste ping externo"
    echo "5 - Sair"
    read escolha_teste 
    if [ $escolha_teste -eq 1 ]; then
        ### Teste dig ###
        echo "Testes de dig:"
        dig empresa.local
    elif [ $escolha_teste -eq 2 ]; then
        ### Teste dig reverso ###
        echo "Teste de dig reverso:"
        dig -x $ip_estatico
    elif [ $escolha_teste -eq 3 ]; then
        ### Teste nslookup ###
        echo "Teste de nslookup:"		
        nslookup servidordns.empresa.local
    elif [ $escolha_teste -eq 4 ]; then
        ### Teste ping esterno ###
        echo "Teste de ping externo:"	
        ping www.google.com	
    elif [ $escolha_teste -eq 5 ]; then
        break
    else
        echo "Escolha inválida. Tente novamente."
    fi
done
