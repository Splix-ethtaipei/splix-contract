// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

import {IReceiverV2} from "../lib/evm-cctp-contracts/src/interfaces/v2/IReceiverV2.sol";
import {TypedMemView} from "../lib/memview-sol/contracts/TypedMemView.sol";
import {MessageV2} from "../lib/evm-cctp-contracts/src/messages/v2/MessageV2.sol";
import {BurnMessageV2} from "../lib/evm-cctp-contracts/src/messages/v2/BurnMessageV2.sol";
import {Ownable2Step} from "../lib/evm-cctp-contracts/src/roles/Ownable2Step.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract ReceiptStorage {
    // ============ Constants ============
    // Address of the local message transmitter
    IReceiverV2 public immutable messageTransmitter;

    // Address of the USDC token
    IERC20 public immutable usdcToken;

    // chain flag
    enum ChainFlag {
        MAINNET,
        SEPOLIA,
        AVALANCHE_C_CHAIN,
        AVALANCHE_FUJI
    }

    ChainFlag public immutable chainFlag;

    // USDC address on different chains
    address constant ETH_MAINNET_USDC_ADDR = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant ETH_SEPOLIA_USDC_ADDR = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant AVALANCHE_C_CHAIN_USDC_ADDR = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address constant AVALANCHE_FUJI_CHAIN_USDC_ADDR = 0x5425890298aed601595a70AB815c96711a31Bc65;

    // The supported Message Format version
    uint32 public constant supportedMessageVersion = 1;

    // The supported Message Body version
    uint32 public constant supportedMessageBodyVersion = 1;

    // Byte-length of an address
    uint256 internal constant ADDRESS_BYTE_LENGTH = 20;

    // ============ Libraries ============
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    // ============ Constructor ============
    /**
     * @param _messageTransmitter The address of the local message transmitter
     * @param _chainFlag The chain flag
     */
    constructor(address _messageTransmitter, ChainFlag _chainFlag) {
        require(_messageTransmitter != address(0), "Message transmitter is the zero address");

        messageTransmitter = IReceiverV2(_messageTransmitter);
        chainFlag = _chainFlag;

        // Determine USDC address based on chain flag parameter
        address usdcAddress;
        if (_chainFlag == ChainFlag.MAINNET) {
            usdcAddress = ETH_MAINNET_USDC_ADDR;
        } else if (_chainFlag == ChainFlag.SEPOLIA) {
            usdcAddress = ETH_SEPOLIA_USDC_ADDR;
        } else if (_chainFlag == ChainFlag.AVALANCHE_C_CHAIN) {
            usdcAddress = AVALANCHE_C_CHAIN_USDC_ADDR;
        } else if (_chainFlag == ChainFlag.AVALANCHE_FUJI) {
            usdcAddress = AVALANCHE_FUJI_CHAIN_USDC_ADDR;
        } else {
            // Default to Sepolia for safety
            usdcAddress = ETH_SEPOLIA_USDC_ADDR;
        }

        // Initialize the immutable variable once
        usdcToken = IERC20(usdcAddress);
    }

    struct GroupInfo {
        string groupName;
        string[] items; // the items could be duplicated i.e. [apple, apple, banana, cookie]
        uint256[] prices; // in usdc, ie. 8dp
    }

    uint256 public groupId;

    // groupId -> owner
    mapping(uint256 => address) public groupOwnerMap;

    // groupId -> itemId -> price
    mapping(uint256 => mapping(uint256 => uint256)) public groupItemPriceMap;

    // groupId -> itemId -> itemName
    mapping(uint256 => mapping(uint256 => string)) public groupItemNameMap;

    // groupId -> itemId -> hasPaid
    mapping(uint256 => mapping(uint256 => bool)) public groupItemHasPaidMap;

    // groupId -> itemId -> paidBy
    mapping(uint256 => mapping(uint256 => address)) public groupItemPaidByMap;

    // groupId -> itemNum
    mapping(uint256 => uint256) public groupItemNumMap;

    // Events for tracking
    event GroupCreated(uint256 indexed groupId, address indexed owner, string groupName, uint256 itemCount);
    event GroupEdited(uint256 indexed groupId, address indexed owner, uint256 itemCount);
    event ItemCreated(uint256 indexed groupId, uint256 indexed itemId, string itemName, uint256 itemPrice);
    event ItemEdited(uint256 indexed groupId, uint256 indexed itemId, string itemName, uint256 itemPrice);
    event ItemsPaid(uint256 indexed groupId, address indexed payer, uint256[] itemIds, uint256 totalAmount);

    modifier onlyGroupOwner(uint256 _groupId) {
        require(msg.sender == groupOwnerMap[_groupId], "Not owner");
        _;
    }

    function createGroup(GroupInfo memory groupInfo) public {
        uint256 currentGroupId = groupId;
        groupOwnerMap[currentGroupId] = msg.sender;
        string memory groupName = groupInfo.groupName;
        string[] memory items = groupInfo.items;
        uint256[] memory prices = groupInfo.prices;
        require(items.length == prices.length, "Items and prices length mismatch");
        require(items.length > 0, "No items provided");

        for (uint256 i = 0; i < items.length; i++) {
            groupItemNameMap[currentGroupId][i] = items[i];
            groupItemPriceMap[currentGroupId][i] = prices[i];
            groupItemHasPaidMap[currentGroupId][i] = false;
            emit ItemCreated(currentGroupId, i, items[i], prices[i]);
        }
        groupItemNumMap[currentGroupId] = items.length;

        // Increment group ID after successful creation
        groupId++;

        emit GroupCreated(currentGroupId, msg.sender, groupName, items.length);
    }

    function editGroup(uint256 _groupId, GroupInfo memory groupInfo) public onlyGroupOwner(_groupId) {
        string[] memory items = groupInfo.items;
        uint256[] memory prices = groupInfo.prices;
        require(items.length == prices.length, "Items and prices length mismatch");
        require(items.length > 0, "No items provided");

        // Clear any existing items that are already paid
        for (uint256 i = 0; i < items.length; i++) {
            require(!groupItemHasPaidMap[_groupId][i], "Cannot edit paid items");
            groupItemNameMap[_groupId][i] = items[i];
            groupItemPriceMap[_groupId][i] = prices[i];
            emit ItemEdited(_groupId, i, items[i], prices[i]);
        }
        groupItemNumMap[_groupId] = items.length;

        emit GroupEdited(_groupId, msg.sender, items.length);
    }

    function payForItems(uint256 _groupId, uint256[] memory itemIds, uint256 amount) public {
        require(itemIds.length > 0, "No items selected");

        // Calculate total price of selected items
        uint256 totalPaid = 0;
        for (uint256 i = 0; i < itemIds.length; i++) {
            uint256 itemId = itemIds[i];
            // Check if item exists and is not paid yet
            require(bytes(groupItemNameMap[_groupId][itemId]).length > 0, "Item does not exist");
            require(!groupItemHasPaidMap[_groupId][itemId], "Item already paid");

            totalPaid += groupItemPriceMap[_groupId][itemId];
        }

        require(totalPaid == amount, "Amount does not match total price of selected items");
        require(usdcToken.balanceOf(msg.sender) == amount, "Incorrect USDC balance");

        // Mark items as paid
        for (uint256 i = 0; i < itemIds.length; i++) {
            uint256 itemId = itemIds[i];
            groupItemHasPaidMap[_groupId][itemId] = true;
            groupItemPaidByMap[_groupId][itemId] = msg.sender;
        }

        usdcToken.transferFrom(msg.sender, groupOwnerMap[_groupId], amount);

        emit ItemsPaid(_groupId, msg.sender, itemIds, amount);
    }

    // View function to get all items and their status in a group
    function getGroupItems(uint256 _groupId)
        public
        view
        returns (string[] memory names, uint256[] memory prices, bool[] memory paidStatus, address[] memory paidBy)
    {
        uint256 itemAmount = groupItemNumMap[_groupId];

        names = new string[](itemAmount);
        prices = new uint256[](itemAmount);
        paidStatus = new bool[](itemAmount);
        paidBy = new address[](itemAmount);

        for (uint256 i = 0; i < itemAmount; i++) {
            names[i] = groupItemNameMap[_groupId][i];
            prices[i] = groupItemPriceMap[_groupId][i];
            paidStatus[i] = groupItemHasPaidMap[_groupId][i];
            paidBy[i] = groupItemPaidByMap[_groupId][i];
        }

        return (names, prices, paidStatus, paidBy);
    }

    // ============ External Functions  ============
    /**
     * @notice Relays a burn message to a local message transmitter
     * and executes the hook, if present.
     *
     * @dev The hook data contained in the Burn Message is expected to follow this format:
     * Field                 Bytes      Type       Index
     * target                20         address    0
     * hookCallData          dynamic    bytes      20
     *
     * The hook handler will call the target address with the hookCallData, even if hookCallData
     * is zero-length. Additional data about the burn message is not passed in this call.
     *
     * @dev Reverts if not called by the Owner. Due to the lack of atomicity with the hook call, permissionless relay of messages containing hooks via
     * an implementation like this contract should be carefully considered, as a malicious caller could use a low gas attack to consume
     * the message's nonce without executing the hook.
     *
     * WARNING: this implementation does NOT enforce atomicity in the hook call. This is to prevent a failed hook call
     * from preventing relay of a message if this contract is set as the destinationCaller.
     *
     * @dev Reverts if the receiveMessage() call to the local message transmitter reverts, or returns false.
     * @param message The message to relay, as bytes
     * @param attestation The attestation corresponding to the message, as bytes
     * @return relaySuccess True if the call to the local message transmitter succeeded.
     */
    function relay(
        bytes calldata message,
        bytes calldata attestation,
        uint256 _groupId,
        uint256[] memory itemIds,
        uint256 amount
    ) external virtual returns (bool relaySuccess) {
        // Validate message
        // 0 to 29 is the msg
        bytes29 _msg = message.ref(0);
        MessageV2._validateMessageFormat(_msg);
        require(MessageV2._getVersion(_msg) == supportedMessageVersion, "Invalid message version");

        // Validate burn message
        bytes29 _msgBody = MessageV2._getMessageBody(_msg);
        BurnMessageV2._validateBurnMessageFormat(_msgBody);
        require(BurnMessageV2._getVersion(_msgBody) == supportedMessageBodyVersion, "Invalid message body version");

        // receiveMessage includes minting USDC token to destination addr(which is this contract)
        relaySuccess = messageTransmitter.receiveMessage(message, attestation);
        require(relaySuccess, "Receive message failed");

        // update the state of these items
        payForItems(_groupId, itemIds, amount);

        return (relaySuccess);
    }
}
