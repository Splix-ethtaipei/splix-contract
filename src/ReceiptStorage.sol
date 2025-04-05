// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;

contract ReceiptStorage {
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

        // Mark items as paid
        for (uint256 i = 0; i < itemIds.length; i++) {
            uint256 itemId = itemIds[i];
            groupItemHasPaidMap[_groupId][itemId] = true;
            groupItemPaidByMap[_groupId][itemId] = msg.sender;
        }

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
}
