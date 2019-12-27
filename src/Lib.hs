{-# LANGUAGE OverloadedStrings          #-}
module Lib
    ( readAndProcess
    ) where
import Data.Ini(readIniFile, lookupValue, Ini(..))
import           Data.Text                  (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

data Configuration = Configuration {
        configDescription :: Text,
        wgPrivateKey :: Text,
        wgPublicKey :: Text,
        wgEndpoint :: Text,
        wgAddresses :: [Text]
} deriving (Show)

wgEndpointPort :: Configuration -> Text
wgEndpointPort config = snd (T.breakOnEnd ":" (wgEndpoint config))

get :: Text -> Text -> Ini -> Text
get section key ini = case (lookupValue section key ini) of
    Right t -> t
    Left problem -> error(problem)

parseIni :: FilePath -> Ini -> Configuration
parseIni description ini = Configuration {
    configDescription = T.pack description,
    wgPrivateKey = get "Interface" "PrivateKey" ini, 
    wgPublicKey = get "Peer" "PublicKey" ini,
    wgEndpoint = get "Peer" "Endpoint" ini,
    wgAddresses = T.splitOn "," (get "Interface" "Address" ini)
}

loadIni :: FilePath -> IO Configuration
loadIni configPath = do
    eitherIni <- readIniFile configPath
    case eitherIni of
        Right ini -> return (parseIni configPath ini)
        Left problem -> error problem

establishedRelated :: [Text]
establishedRelated = [
    "set description 'established only'",
    "set default-action drop",
    "set rule 10 action accept",
    "set rule 10 state established enable",
    "set rule 10 state related enable"
    ]

-- 190 == mul
edgerouterConfigurationFrom :: Configuration -> Text
edgerouterConfigurationFrom c = T.unlines $ [
    "configure",
    "# Wireguard firewalls",
    "edit firewall name wgIn"  ] ++ establishedRelated ++ [ "exit",
    "edit firewall name wgLocal"  ] ++ establishedRelated ++ [ "exit",
    "edit firewall ipv6-name wgIn6" ] ++ establishedRelated ++ [ "exit",
    "edit firewall ipv6-name wgLocal6" ] ++ establishedRelated ++ [ "exit",
    "# Interfaces",
    "edit interfaces wireguard wg0",
    T.concat ["set description '" , (configDescription c), "'"]
    ] ++ (map (\x -> T.concat ["set address ", x]) (wgAddresses c)) ++ [
    "set listen-port 51820",
    "set route-allowed-ips false",
    T.concat ["set peer '" , wgPublicKey c, "' endpoint ", wgEndpoint c],
    T.concat ["set peer '" , wgPublicKey c, "' allowed-ips 0.0.0.0/0"],
    T.concat ["set peer '" , wgPublicKey c, "' allowed-ips ::0/0"],
    T.concat ["set private-key '" , wgPrivateKey c, "'"],
    "set fwmark 190",
    "set firewall in name wgIn",
    "set firewall in ipv6-name wgIn6",
    "set firewall local name wgLocal",
    "set firewall local ipv6-name wgLocal6",
    "exit",
    "edit protocols static table 190",
    "set description 'mullvad'",
    "set interface-route 0.0.0.0/0 next-hop-interface wg0",
    "exit",
    "edit protocols static table 196",
    "set description 'mullvad6'",
    "set interface-route6 ::0/0 next-hop-interface wg0",
    "exit",
    "edit service nat rule 5190",
    "set description 'masq mullvad'",
    "set outbound-interface wg0",
    "set type masquerade",
    "exit",
    "# Example of using modify to put traffic into the tunnel route table",
    "edit firewall modify lanInModify rule 190",
    "set action modify",
    "set modify table 190",
    "exit",
    "edit firewall ipv6-modify lanInModify6 rule 190",
    "set action modify",
    "set modify table 196",
    "exit",
    "# apply special routing table by adding modify rules to local network interfaces",
    "set interfaces switch switch0 firewall in modify lanInModify",
    "set interfaces switch switch0 firewall in ipv6-modify lanInModify6",
    "# accept incoming wireguard packets to this host",
    "edit firewall name wanLocal rule 190",
    "set action accept",
    "set description 'accept wireguard'",
    "set destination port 51820",
    "set protocol udp",
    "exit",
    "edit firewall ipv6-name wanLocal6 rule 190",
    "set action accept",
    "set description 'accept wireguard'",
    "set destination port 51820",
    "set protocol udp",
    "exit",
    "edit protocols static interface-route 10.8.0.1/32",
    "set description 'in-tunnel dns'",
    "set next-hop-interface wg0",
    "exit",
    "# commit",
    "# exit",
    "## ipv6 nat is not supported by ubiquity yet",
    "# sudo ip6tables --table nat --append POSTROUTING --out-interface wg0 -j MASQUERADE",
    ""
    ]


readAndProcess :: FilePath -> IO ()
readAndProcess configPath = do
    configuration <- loadIni configPath
    TIO.putStrLn $ edgerouterConfigurationFrom configuration