// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ERC2771Context {
    address private _trustedForwarder;

    constructor(address trustedForwarder) {
        _trustedForwarder = trustedForwarder;
    }

    function isTrustedForwarder(address forwarder)
        public
        view
        returns (bool)
    {
        return forwarder == _trustedForwarder;
    }

    function _msgSender()
        internal
        view
        virtual
        returns (address sender)
    {
        if (isTrustedForwarder(msg.sender)) {
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            sender = msg.sender;
        }
    }
}

contract GaslessCounter is ERC2771Context {

    uint256 public counter;

    constructor(address forwarder)
        ERC2771Context(forwarder)
    {}

    function increment() external {
        address realUser = _msgSender();
        counter += 1;
    }
}