// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MultiSigWallet {

    event Deposit(address indexed owner, uint amount);
    event TransactionSubmitted(
        uint indexed txId,
        address indexed to,
        uint value,
        bytes data
    );
    event TransactionApproved(address indexed  owner ,uint indexed txId);
    event TransactionExecuted(uint indexed txId);

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint requestedApprovals;

    struct Transaction {
        address to;
        uint value;
        bytes data;
        bool executed;
        uint approvalCount;
    }

    Transaction[] public transactions;
    mapping (uint => mapping(address => bool)) public approved;

    modifier onlyOwner {
        require(isOwner[msg.sender], "Not an Owner");
        _;
    }

    modifier txExists(uint id) {
        require(id < transactions.length, "Transaction not exists");
        _;
    }

    modifier notExecuted(uint id){
        require(!transactions[id].executed, "Transaction not executed");
        _;
    }

    modifier notApproved(uint id) {
        require(!approved[id][msg.sender], "Transaction not approved");
        _;
    }

    constructor(address[] memory _owners, uint _requestedApprovals) payable{
        require(_owners.length > 0, "Owners required");
        require(_requestedApprovals > 0 && _requestedApprovals <= _owners.length, "Invalid approval requirements");
        for(uint i = 0; i < _owners.length; i++){
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Duplicate owner");
            isOwner[owner] = true;
            owners.push(owner);
        }
        requestedApprovals = _requestedApprovals;
    }

    receive() external payable { 
        emit Deposit(msg.sender, msg.value);
    }

    function transactionSubmit(address _to, uint _value, bytes calldata _data) external onlyOwner{
        uint txId = transactions.length;
        transactions.push(Transaction({
            to: _to,
            value: _value,
            data: _data,
            executed: false,
            approvalCount: 0
        }));
        emit TransactionSubmitted(txId, _to, _value, _data);
    }

    function approveTransaction(uint txId) external onlyOwner notApproved(txId) notExecuted(txId) txExists(txId) {
        approved[txId][msg.sender] = true;
        transactions[txId].approvalCount += 1;
        emit TransactionApproved(msg.sender, txId);
    }

    function executeTransaction(uint txId) external onlyOwner txExists(txId) notExecuted(txId) {
        Transaction storage txn = transactions[txId];
        require(txn.approvalCount >= requestedApprovals, "Insufficient Approvals");
        txn.executed = true;
        (bool success,) = txn.to.call{value: txn.value}(txn.data);
        require(success, "Transaction failed");

        emit TransactionExecuted(txId);
    }

    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function getTransactionCount() external view returns (uint) {
        return transactions.length;
    }

    function getTransaction(uint _txId) external view returns (address to, uint value, bytes memory data, bool executed, uint approvalCount) {
        Transaction storage txn = transactions[_txId];
        return (txn.to, txn.value, txn.data, txn.executed, txn.approvalCount);
    }
}
