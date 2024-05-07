// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.22;

import { console2 } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IProxyRegistry } from "../src/external/opensea/IProxyRegistry.sol";
import { INounsDescriptor } from "../src/interfaces/INounsDescriptor.sol";

import { NounsDescriptor } from "../src/NounsDescriptor.sol";
import { INounsSeeder } from "../src/interfaces/INounsSeeder.sol";
import { LilVRGDA } from "../src/LilVRGDA.sol";
import { NounsSeederV2 } from "../src/NounsSeederV2.sol";
import { ERC1967Proxy } from "../src/proxy/ERC1967Proxy.sol";
import { NounsToken } from "../src/NounsToken.sol";

contract DeployContracts is Script {
    using Strings for uint256;

    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address descriptor;

    address seeder;

    address token;

    address vrgdaImpl;

    address vrgdaProxy;

    function run() public {
        uint256 chainID = vm.envUint("CHAIN_ID");
        uint256 key = vm.envUint("PRIVATE_KEY");

        address deployerAddress = vm.addr(key);

        vm.startBroadcast(deployerAddress);

        // TODO remove for prod deployment
        descriptor = deployDescriptor();

        vrgdaImpl = deployVRGDAImpl();

        vrgdaProxy = deployVRGDAProxy();

        seeder = deploySeeder();

        initializeVRGDAProxy();

        // TODO remove for prod deployment
        token = deployToken();

        vm.stopBroadcast();

        writeDeploymentDetailsToFile(chainID);
    }

    function deployDescriptor() private returns (address) {
        return address(new NounsDescriptor());
    }

    function deploySeeder() private returns (address) {
        return address(new NounsSeederV2(vrgdaProxy));
    }

    function deployToken() private returns (address) {
        return
            address(
                new NounsToken(
                    0x3cf6a7f06015aCad49F76044d3c63D7fE477D945, // Address of the lilnounders DAO
                    0x0BC3807Ec262cB779b38D65b38158acC3bfedE10, // Address of the nouns DAO
                    vrgdaProxy, // Address of the minter
                    INounsDescriptor(descriptor), // Address of the descriptor
                    INounsSeeder(seeder), // Address of the seeder
                    IProxyRegistry(0xa5409ec958C83C3f309868babACA7c86DCB077c1) // Address of the OpenSea proxy registry
                )
            );
    }

    function deployVRGDAImpl() private returns (address) {
        int256 targetPrice = 0.15 * 1e18; // 0.15 ETH
        int256 priceDecayPercent = 1e18 / 5; // 20% scaled by 1e18
        int256 perTimeUnit = 1e18; // 1 NFT sold per day

        return address(new LilVRGDA(targetPrice, priceDecayPercent, perTimeUnit, weth));
    }

    function deployVRGDAProxy() private returns (address) {
        return address(new ERC1967Proxy(vrgdaImpl, ""));
    }

    function initializeVRGDAProxy() private {
        uint256 nextNounId = 7974 + 1;
        uint256 poolSize = 4;
        uint256 nounsSoldAtAuction = 0;
        uint256 reservePrice = 0.15 * 1e18;

        LilVRGDA(vrgdaProxy).initialize({
            _nextNounId: nextNounId,
            _poolSize: poolSize,
            _nounsSoldAtAuction: nounsSoldAtAuction,
            _reservePrice: reservePrice,
            _nounsSeederAddress: seeder,
            _nounsDescriptorAddress: descriptor,
            _nounsTokenAddress: token
        });
    }

    function writeDeploymentDetailsToFile(uint256 chainID) private {
        string memory filePath = string(abi.encodePacked("deploys/", chainID.toString(), ".txt"));

        vm.writeFile(filePath, "");
        vm.writeLine(filePath, string(abi.encodePacked("Descriptor: ", addressToString(descriptor))));
        vm.writeLine(filePath, string(abi.encodePacked("VRGDA Impl: ", addressToString(vrgdaImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("VRGDA Proxy: ", addressToString(vrgdaProxy))));
        vm.writeLine(filePath, string(abi.encodePacked("Seeder: ", addressToString(seeder))));
        vm.writeLine(filePath, string(abi.encodePacked("Token: ", addressToString(token))));
    }

    function addressToString(address _addr) private pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(_addr)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(abi.encodePacked("0x", string(s)));
    }

    function char(bytes1 b) private pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
