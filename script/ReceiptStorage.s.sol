// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import {Script, console} from "forge-std/Script.sol";
import {ReceiptStorage} from "../src/ReceiptStorage.sol";

contract ReceiptStorageScript is Script {
    address constant MSG_TRANSMITTER = 0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;

    ReceiptStorage public receiptStorage;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        
        // Get chain flag from environment variable or use a default
        string memory chainName = vm.envOr("CHAIN", string("sepolia"));
        ReceiptStorage.ChainFlag chainFlag;
        
        // Set chain flag based on network name
        if (keccak256(bytes(chainName)) == keccak256(bytes("mainnet"))) {
            chainFlag = ReceiptStorage.ChainFlag.MAINNET;
        } else if (keccak256(bytes(chainName)) == keccak256(bytes("sepolia"))) {
            chainFlag = ReceiptStorage.ChainFlag.SEPOLIA;
        } else if (keccak256(bytes(chainName)) == keccak256(bytes("avalanche"))) {
            chainFlag = ReceiptStorage.ChainFlag.AVALANCHE_C_CHAIN;
        } else if (keccak256(bytes(chainName)) == keccak256(bytes("fuji"))) {
            chainFlag = ReceiptStorage.ChainFlag.AVALANCHE_FUJI;
        } else {
            // Default to Sepolia
            chainFlag = ReceiptStorage.ChainFlag.SEPOLIA;
        }
        
        console.log("Deploying ReceiptStorage on", chainName);
        receiptStorage = new ReceiptStorage(MSG_TRANSMITTER, chainFlag);

        vm.stopBroadcast();
    }
}
