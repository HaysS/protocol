pragma solidity ^0.4.21;

import "../instruments/AbacusERC20Token.sol";

/**
 * @dev Faucet token
 */
contract FaucetToken is AbacusERC20Token {
    uint8 public constant decimals = 18;
    uint256 public constant INITIAL_SUPPLY = 1000000000000000000 * (10 ** uint256(decimals));
    uint256 constant faucetAmt = 1000 * (10 ** uint256(decimals));

    function FaucetToken(
        ComplianceCoordinator _complianceCoordinator,
        uint256 _complianceProviderId
    ) AbacusERC20Token(_complianceCoordinator, _complianceProviderId) public
    {
        totalSupply_ = INITIAL_SUPPLY;
        balances[this] = INITIAL_SUPPLY;
        emit Transfer(0x0, this, INITIAL_SUPPLY);
    }

    function request() public {
        balances[msg.sender] += faucetAmt;
        balances[this] -= faucetAmt;
        emit Transfer(this, msg.sender, faucetAmt);
    }
}