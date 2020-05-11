# mullvad-edgerouter-x
Generate Edgerouter X configuration from [Mullvad](https://mullvad.net) Wireguard configuration.

This is a Python script that reads [Mullvad configuration](mullvad-example.conf) and generated [Ubiquity configuration commands for wireguard](mullvad-example_commands.txt).

Usage
-----

- Download the mullvad edgerouter configuration. You should have a config file that looks like [the example configuration](mullvad-example.conf)
- Run the python script with your mullvad configuration as an argument

    python3 merc.py mullvad-nl2.conf

- The script will write out a file where `.conf` is replaced by `_commands.txt` which will contain a list of commands to configure your edgerouter
- By hand copy and paste all the commands from the commands file into your edgerouter via an SSH terminal, making sure **you understand each and every command**.

Feel free to edit the script, send pull requests or open up issues on this github project.

IPv6 NAT support on Edgerouter
------------------------------
The edgerouter does not support IPv6 as a masquarade interface, luckily it's based on Linux which does support this.

You can use the following `iptables` command to add full IPv6 NAT support to the `wg0` interface defined by the commands:

    /sbin/ip6tables --table nat --append POSTROUTING --out-interface wg0 -j MASQUERADE


Explaination of each of the command blocks
------------------------------------------

The commands create a wireguard interface with firewall rules and a separate routing table. The separate routing table is used to route the traffic onto the wireguard interface. To put traffice on that routing table, you need to have a `modify` firewall rule that changes the routing table to `190` (the number for the routing table).

Current configuration will put everything from the local lan on that routing table, but leaves the router itself out of this. This means that the edgerouter will still use the direct internet connection: updates, NTP, dns, unms etc. will probably end up outside of the tunnel if don't take extra precautions.

Now for each block of commands a quick piece of text to explain:


    edit firewall name wgIn

    set description 'established only'
    set default-action drop
    set rule 10 action accept
    set rule 10 state established enable
    set rule 10 state related enable
    exit

Meant for the incoming traffic on the wireguard interface. This will only allow related and established traffic through this interface, the rest is dropped. This is also repeated for connections to the local services on the router in the `wgLocal` firewall and duplicated for IPv6 in the `wgIn6` and `wgLocal6` firewalls.

    # Interfaces
    edit interfaces wireguard wg0
    set description 'mullvad-example.conf'
    set address 10.64.131.1/32
    set address fc00:bbbb:bbbb:bb01::1:844c/128
    set listen-port 51820
    set route-allowed-ips false
    set peer 'fake-public-key' endpoint 185.65.134.224:51820
    set peer 'fake-public-key' allowed-ips 0.0.0.0/0
    set peer 'fake-public-key' allowed-ips ::0/0
    set private-key fake-private-key
    set fwmark 190
    set firewall in name wgIn
    set firewall in ipv6-name wgIn6
    set firewall local name wgLocal
    set firewall local ipv6-name wgLocal6
    exit

This block sets up the wireguard interface using the information from the configuration file. The last rules hook up the firewall defined earlier.

    edit protocols static table 190
    set description 'mullvad'
    set interface-route 0.0.0.0/0 next-hop-interface wg0
    exit

This is the routing table we use to route all targets that are not local to the device over the wireguard interface. Any traffic that we `modify` to use this route table will end up leaving the edgerouter over the `wg0` interface.

    edit service nat rule 5190
    set description 'masq mullvad'
    set outbound-interface wg0
    set type masquerade
    exit

On the wireguard interface, the edgerouter has the addresses specified in the `wg0` interface definition and we are only allowed to generate traffic from that IP on this interface, so we must make sure to masquerade all the traffic on this interface.

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

This is a firewall rule that will apply the wireguard routing table to any traffic that is no in the address group of `eth0` (where we assume the internet is hooked up) and not in the traffice group of `switch0` which we assume is a switch containing all LAN devices. This is where your configuration may have to differ from the scripts, as you own internet setup may differ.

The last rule will apply the wireguard routing table to any traffic that makes it this far in the firewall.

    set interfaces switch switch0 firewall in modify lanInModify

Here we apply the defined firewall to the LAN interface (`switch0` for my setup).

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

These two rules should not be required if you always initiate the wireguard connection, because these allow any UDP traffice on 51820 to go through.

    edit protocols static interface-route 10.8.0.1/32
    set next-hop-interface wg0
    exit

This command will add a static route to make sure that the router will always try to use the `wg0` interface if it's looking for the Mullvad internal DNS server.

    sudo ip6tables --table nat --append POSTROUTING --out-interface wg0 -j MASQUERADE

The edgerouter does not support masquarade on IPv6, luckily it's based on Linux which does support this. This last command is not part of the `configure` interface of Ubiquity and is therefore commented out in the output and should be run after committing all the changes.
