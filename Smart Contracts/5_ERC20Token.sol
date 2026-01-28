// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MyToken {

    string public name = "MyToken";
    string public symbol = "MTC";
    uint8 public decimals = 18;
    uint public totalSupply;

    address public owner;

    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    // 🔔 Events (REQUIRED for ERC-20)
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);

    constructor(uint initialSupply) {
        owner = msg.sender;
        totalSupply = initialSupply * (10 ** decimals);
        balanceOf[owner] = totalSupply;

        emit Transfer(address(0), owner, totalSupply);
    }

    // ✅ ERC-20 standard signature
    function transfer(address to, uint value) public returns (bool) {
        require(to != address(0), "Invalid address");
        require(balanceOf[msg.sender] >= value, "Balance is not sufficient");

        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;

        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint value) public returns (bool) {
        require(spender != address(0), "Invalid address");

        allowance[msg.sender][spender] = value;

        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) public returns (bool) {
        require(from != address(0), "Invalid from address");
        require(to != address(0), "Invalid to address");
        require(balanceOf[from] >= value, "Balance is not sufficient");
        require(allowance[from][msg.sender] >= value, "Allowance exceeded");

        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;

        emit Transfer(from, to, value);
        return true;
    }

    function mint(uint value) public {
        require(msg.sender == owner, "Only owner can create tokens");

        totalSupply += value;
        balanceOf[owner] += value;

        emit Transfer(address(0), owner, value);
    }

    function burn(uint value) public {
        require(balanceOf[msg.sender] >= value, "Not enough tokens");

        balanceOf[msg.sender] -= value;
        totalSupply -= value;

        emit Transfer(msg.sender, address(0), value);
    }
}

// Using OpenZepplin
// pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

// contract MyToken is ERC20, Ownable {

//     bool public paused;

//     // 🔹 Modifier
//     modifier whenNotPaused() {
//         require(!paused, "Token transfers are paused");
//         _;
//     }

//     constructor(uint initialSupply) ERC20("MyToken", "MTC") {
//         _mint(msg.sender, initialSupply * 10 ** decimals());
//     }

//     // 🔹 Override transfer with pause feature
//     function transfer(address to, uint amount)
//         public
//         override
//         whenNotPaused
//         returns (bool)
//     {
//         return super.transfer(to, amount);
//     }

//     // 🔹 Override transferFrom with pause feature
//     function transferFrom(address from, address to, uint amount)
//         public
//         override
//         whenNotPaused
//         returns (bool)
//     {
//         return super.transferFrom(from, to, amount);
//     }

//     // 🔹 Owner can mint
//     function mint(address to, uint amount) public onlyOwner {
//         _mint(to, amount);
//     }

//     // 🔹 Anyone can burn their own tokens
//     function burn(uint amount) public {
//         _burn(msg.sender, amount);
//     }

//     // 🔹 Pause / Unpause
//     function pause() public onlyOwner {
//         paused = true;
//     }

//     function unpause() public onlyOwner {
//         paused = false;
//     }
// }

