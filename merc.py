#!/usr/bin/python
import configparser
import sys
from string import Template
import textwrap

established_related = textwrap.dedent("""
    set description 'established only'
    set default-action drop
    set rule 10 action accept
    set rule 10 state established enable
    set rule 10 state related enable"""
)

config_template = Template(
    textwrap.dedent("""
    configure
    
    # Wireguard firewalls
    edit firewall name wgIn
    $established_related
    exit
    
    edit firewall name wgLocal
    $established_related
    exit
    
    edit firewall ipv6-name wgIn6
    $established_related
    exit

    edit firewall ipv6-name wgLocal6
    $established_related
    exit

    # Interfaces
    edit interfaces wireguard wg0
    set description '$config_descriptor'
    set address $interface_address0
    set address $interface_address1
    set listen-port 51820
    set route-allowed-ips false
    set peer '$peer_publickey' endpoint $peer_endpoint
    set peer '$peer_publickey' allowed-ips 0.0.0.0/0
    set peer '$peer_publickey' allowed-ips ::0/0
    set private-key $interface_privatekey
    set fwmark 190
    set firewall in name wgIn
    set firewall in ipv6-name wgIn6
    set firewall local name wgLocal
    set firewall local ipv6-name wgLocal6
    exit
    edit protocols static table 190
    set description 'mullvad'
    set interface-route 0.0.0.0/0 next-hop-interface wg0
    exit
    edit service nat rule 5190
    set description 'masq mullvad'
    set outbound-interface wg0
    set type masquerade
    exit
    
    # Example of using modify to put traffic into the tunnel route table
    edit firewall modify lanInModify rule 187
    set description 'do not mod wireguard ever'
    set action accept
    set destination port 51820
    set protocol udp
    exit
    edit firewall modify lanInModify rule 188
    set description 'allow access to ISP modem'
    set action accept
    set destination group address-group NETv4_eth0
    exit
    edit firewall modify lanInModify rule 189
    set description 'do not mod local targets'
    set action accept
    set destination group address-group NETv4_switch0
    exit
    edit firewall modify lanInModify rule 190
    set action modify
    set modify table 190
    exit
    
    # apply special routing table by adding modify rules to local network interfaces
    set interfaces switch switch0 firewall in modify lanInModify
    # accept incoming wireguard packets to this host
    edit firewall name wanLocal rule 190
    set action accept
    set description 'accept wireguard input'
    set destination port 51820
    set protocol udp
    exit
    edit firewall ipv6-name wanLocal6 rule 190
    set action accept
    set description 'accept wireguard input'
    set destination port 51820
    set protocol udp
    exit
    edit protocols static interface-route 10.8.0.1/32
    set next-hop-interface wg0
    exit
    # DONE, use commit to commit to current configuration
    # Never run save without testing first!
    ## ipv6 nat is not supported by ubiquity yet
    # sudo ip6tables --table nat --append POSTROUTING --out-interface wg0 -j MASQUERADE
    """
    )
)


def main() -> int:
    config_file = sys.argv[1]
    print("Reading from:", config_file)
    mullvad_config = configparser.ConfigParser()
    mullvad_config.read(config_file)
    edgerouter_config = config_template.substitute(
        config_descriptor=config_file,
        established_related=established_related,
        interface_address0=mullvad_config["Interface"]["Address"].split(",")[0],
        interface_address1=mullvad_config["Interface"]["Address"].split(",")[1],
        interface_privatekey=mullvad_config["Interface"]["PrivateKey"],
        peer_publickey=mullvad_config["Peer"]["PublicKey"],
        peer_endpoint=mullvad_config["Peer"]["Endpoint"],
    )
    edgerouter_config = edgerouter_config.strip()
    
    output_name = config_file.replace(".conf", "_commands.txt")
    if not output_name.endswith(".txt"):
        output_name = output_name + ".txt"
    assert output_name != config_file, "Never overwrite input file"
    with open(output_name, "w") as output_file:
        output_file.write(edgerouter_config)
    print("Written to:", output_name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
